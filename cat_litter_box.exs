# Logs the cat's weight from a Tuya litter box to Arrow files in log/:  elixir cat_litter_box.exs
# Tuya pushes each report over a WebSocket. Anything unexpected stops the script, but a connection
# that drops is made again.
#
# Tuya pushes nothing until all of this is done on https://platform.tuya.com. Without any one step
# the socket connects and Tuya answers its pings, but no report ever comes, and nothing says why:
#
#   1. Cloud → Development → Create Cloud Project, in the data centre of the app account: Central
#      Europe here, which is the host mqe.tuyaeu.com below. Its Overview has the Access ID and the
#      Access Secret, which go in TUYA_ACCESS_ID and TUYA_ACCESS_SECRET in the environment.
#   2. Devices → Link App Account → Add App Account, and scan the QR code in the Tuya or Smart Life
#      app of the account that owns the litter box. A device only shared with the linked account
#      reads fine over REST but is never pushed: the owner's account must be the one linked.
#   3. Message Service: turn it on, as a Message Queue.
#   4. Message Service → Messaging Rules → Production Environment → Create Messaging Rules: Add
#      Message Filtering Rule, BizCode (Message Type) In devicePropertyMessage and
#      deviceEventMessage, then Release Rule and OK.
#   5. Then turn on the switch beside "The rules for the production environment are disabled": a
#      released rule pushes nothing until it is on. The page then says the rules are in effect.
#
# To test it, change a setting of the litter box in the app: the script prints a "report:" line
# within seconds. @device below is the device's id, from the project's Devices list.
Mix.install([{:xignal, path: Path.expand("~/xignal")}, {:websockex, "~> 0.5"}, {:req, "~> 0.7"}])

defmodule Tuya do
  use WebSockex
  md5 = &Base.encode16(:crypto.hash(:md5, &1), case: :lower)

  @id System.fetch_env!("TUYA_ACCESS_ID")
  @secret System.fetch_env!("TUYA_ACCESS_SECRET")
  @password String.slice(md5.(@id <> md5.(@secret)), 8, 16)
  @key String.slice(@secret, 8, 16)
  @host "wss://mqe.tuyaeu.com:8285"
  @url "#{@host}/ws/v2/consumer/persistent/#{@id}/out/event/#{@id}-sub?subscriptionType=Failover"
  @code "cat_weight"
  @device "bf4bc5a9ded01ca8c4ovdo"

  def start(weight, activity_notice) do
    headers = [{"username", @id}, {"password", @password}]
    state = %{weight: weight, activity_notice: activity_notice, pong: true}

    WebSockex.start_link(@url, __MODULE__, state,
      extra_headers: headers,
      name: __MODULE__
    )
  end

  def handle_connect(_conn, state) do
    log("connected")
    {:ok, %{state | pong: true}}
  end

  # The program sends :ping when no message has come for 4 minutes, see Cat.watch. A connection can
  # stop delivering without closing, so a ping that has no pong by the next one closes it, and the
  # socket connects again.
  def handle_info(:ping, %{pong: false} = state) do
    log("no pong, reconnecting")
    {:close, state}
  end

  def handle_info(:ping, state), do: {:reply, :ping, %{state | pong: false}}

  def handle_pong(_frame, state), do: {:ok, %{state | pong: true}}

  def handle_disconnect(%{reason: reason}, state) do
    log("disconnected: #{inspect(reason)}")
    Process.sleep(5_000)
    {:reconnect, state}
  end

  defp log(text), do: IO.puts("#{DateTime.utc_now() |> DateTime.truncate(:second)} #{text}")

  # A message is JSON in base64 in JSON, with its data encrypted by a part of the secret. Every one is
  # told to the program as the event :activity_notice, which shows the connection is alive.
  def handle_frame({:text, frame}, %{weight: weight} = state) do
    Xignal.Store.trigger(state.activity_notice)

    %{"messageId" => id, "payload" => payload, "properties" => %{"em" => mode}} =
      JSON.decode!(frame)

    data = payload |> Base.decode64!() |> JSON.decode!() |> Map.fetch!("data") |> Base.decode64!()
    text = decrypt(mode, data)
    report = JSON.decode!(text)
    log("report: #{text}")
    values = report["status"] || get_in(report, ["bizData", "properties"]) || []

    # The device reports the weight in units of 100 g, as a number or as text.
    for %{"code" => @code, "value" => units} <- values, units = number(units), units != nil do
      Xignal.Store.put(weight, units * 100)
    end

    {:reply, {:text, JSON.encode!(%{messageId: id})}, state}
  end

  defp number(units) when is_number(units), do: units

  defp number(units) when is_binary(units) do
    case Integer.parse(units) do
      {n, ""} -> n
      _other -> nil
    end
  end

  defp number(_units), do: nil

  # The weight now, in grams, asked of the REST API: a report is pushed only when the weight changes.
  def current_weight do
    token = get("/v1.0/token?grant_type=1", "")["access_token"]
    status = get("/v1.0/devices/#{@device}/status", token)
    hd(for %{"code" => @code, "value" => units} <- status, do: units * 100)
  end

  # A request signed with the secret, as Tuya's API asks. The header names keep their underscores,
  # which Req would turn into dashes in atom names.
  defp get(path, token) do
    sha256 = &Base.encode16(:crypto.hash(:sha256, &1), case: :lower)
    t = Integer.to_string(System.os_time(:millisecond))
    to_sign = [@id, token, t, "GET\n", sha256.(""), "\n\n", path]
    sign = Base.encode16(:crypto.mac(:hmac, :sha256, @secret, to_sign))
    headers = [{"client_id", @id}, {"sign", sign}, {"t", t}, {"sign_method", "HMAC-SHA256"}]
    headers = if token == "", do: headers, else: [{"access_token", token} | headers]

    %{status: 200, body: %{"success" => true, "result" => result}} =
      Req.get!("https://openapi.tuyaeu.com" <> path, headers: headers)

    result
  end

  defp decrypt("aes_gcm", <<iv::binary-12, rest::binary>>) do
    size = byte_size(rest) - 16
    <<text::binary-size(size), tag::binary>> = rest
    :crypto.crypto_one_time_aead(:aes_128_gcm, @key, iv, text, "", tag, false)
  end

  defp decrypt(_ecb, data) do
    :crypto.crypto_one_time(:aes_128_ecb, @key, data, encrypt: false, padding: :pkcs_padding)
  end
end

# A push notification to this topic on ntfy.sh, which the ntfy app subscribes to. The topic name is
# the only secret. Each is sent from its own process, so that the scan never waits for the network.
defmodule Ntfy do
  @url "https://ntfy.sh/kattedo-53d05ded1cab7a1e6e5dcd3184a327c9"

  def send(message) do
    Task.start(fn ->
      %{status: 200} = Req.post!(@url, body: message, headers: [{"title", "Kattedo"}])
    end)
  end
end

# Which of the three cats a weight is, by weight alone. The weigh-ins of 6 to 12 October 2026 fell in
# three groups, 4.47, 4.97 and 5.71 kg on average, each about 0.17 kg apart around it; the bounds are
# halfway between. Prins and Bamse overlap, so 4.7 or 4.8 kg is now and then the other one. Less
# than 4 kg is a cat partly on the scale.
defmodule Cats do
  def weighed(grams) when grams < 4000, do: "For lett for å bestemme hvem (#{kg(grams)})"
  def weighed(grams) when grams < 4750, do: "Prins #{kg(grams)}"
  def weighed(grams) when grams < 5350, do: "Bamse #{kg(grams)}"
  def weighed(grams), do: "Diva #{kg(grams)}"

  defp kg(grams) do
    String.replace(:erlang.float_to_binary(grams / 1000, decimals: 1), ".", ",") <> " kg"
  end
end

# The program's logic, as one xignal.
defmodule Cat do
  use Xignal

  # Tells on ntfy which cat it was and its weight when the weight has changed, but at most once a
  # minute: the log keeps every change, the notifications only what the weight settled at. The flanks go with the store the
  # weight is read from, so the runner scans them without a sink.
  #
  # And keeps the socket open: Tuya closes a quiet connection after 5 minutes. Each message Tuya
  # sends is a pulse of `activity_notice`; once none has come for 4 minutes the socket is pinged,
  # and every 4 minutes after that, as the timer starts over in the scan after it fires.
  xignal watch(weight, activity_notice) do
    settled = lossy(weight, min: ~t(1m))
    settled |> changed() |> do_on_flank(fn -> Ntfy.send(Cats.weighed(settled)) end)

    pinged = tag(:pinged, prev: true, default: false)

    ton(not activity_notice and not pinged, ~t(4m))
    |> tag(:pinged)
    |> send_on_flank(Tuya, :ping)
  end
end

# The socket writes the weight, in grams, to the store; the runner reads it with its quality, and the
# historian logs a row when it has changed and once a day without that, kept for five years, with the
# quality beside it. Until the store has heard from the socket's partition and the weight now has been
# read, the weight is not good: the historian holds it back for a minute and the notifications pass it
# over, so the runner starts at once, before Tuya has answered.
tuya_store = Xignal.Store.new(:tuya)
weight_to_store = Xignal.Store.output(tuya_store, :cat_weight, default: 0, desc: "Cat weight, g")
activity_notice_to_store = Xignal.Store.event(tuya_store, :activity_notice, desc: "A Tuya message")
Xignal.Store.start(tuya_store)

history =
  Xignal.Historian.new(
    backend:
      {Xignal.Historian.Arrow,
       dir: Path.join(__DIR__, "log"), expiry: 5 * 365 * Xignal.t("1d")},
    flush: Xignal.t("10s")
  )

cat_store = Xignal.Store.new(:cat_logger)
weight_from_store = Xignal.Store.input_q(cat_store, :tuya, :cat_weight, default: 0)
activity_notice_from_store = Xignal.Store.fired(cat_store, :tuya, :activity_notice)

Xignal.Historian.sink(
  weight_from_store,
  Xignal.Historian.output_q(history, "cat", field: :weight_g, min: 0, heartbeat: Xignal.t("1d"))
)

Cat.watch(weight_from_store, activity_notice_from_store)

# Listens to Tuya, and writes the weight now to the store, as Tuya pushes a report only when the
# weight changes. The task stays, so that a socket that fails takes the script with it.
{:ok, _listener} =
  Task.start_link(fn ->
    {:ok, _socket} = Tuya.start(weight_to_store, activity_notice_to_store)
    initial = Tuya.current_weight()
    Xignal.Store.put(weight_to_store, initial)
    Ntfy.send("Startet logging, siste veiing: #{Cats.weighed(initial)}")
    Process.sleep(:infinity)
  end)

Xignal.Runner.run_forever([history, cat_store], Xignal.t("1s"))
