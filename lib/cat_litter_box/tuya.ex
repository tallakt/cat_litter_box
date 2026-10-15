defmodule CatLitterBox.Tuya do
  @moduledoc """
  The WebSocket that Tuya pushes the litter box's reports over. It writes the weight, in grams, what
  the box is doing (`data_identification`: "Standby", "Cleaning", "Reset_Pause" and so on), and an
  event for every message to the store's `:tuya` partition, and reads the weight and the state now
  over Tuya's REST API each time it connects, as a report is pushed only when one changes.
  """

  use WebSockex

  @host "wss://mqe.tuyaeu.com:8285"
  @code "cat_weight"
  @state "data_identification"
  @device "bf4bc5a9ded01ca8c4ovdo"

  # The keys are read as it starts, from the environment; the password and the key that decrypts the
  # messages are parts of the secret.
  def start_link(_opts) do
    id = System.fetch_env!("TUYA_ACCESS_ID")
    secret = System.fetch_env!("TUYA_ACCESS_SECRET")
    keys = %{id: id, secret: secret, key: String.slice(secret, 8, 16)}
    password = String.slice(md5(id <> md5(secret)), 8, 16)
    url = "#{@host}/ws/v2/consumer/persistent/#{id}/out/event/#{id}-sub?subscriptionType=Failover"
    state = %{keys: keys, pong: true}

    WebSockex.start_link(url, __MODULE__, state,
      extra_headers: [{"username", id}, {"password", password}],
      name: __MODULE__
    )
  end

  defp md5(text), do: Base.encode16(:crypto.hash(:md5, text), case: :lower)

  @impl WebSockex
  def handle_connect(_conn, state) do
    log("connected")
    send(self(), :read_weight)
    {:ok, %{state | pong: true}}
  end

  # The weight and the state now, after each connect, and after the first since the node started, a
  # notification that it runs: a socket that is started again does not tell it again.
  @impl WebSockex
  def handle_info(:read_weight, state) do
    {weight, box} = current(state.keys)
    Xignal.Store.put(:tuya, :cat_weight, weight)
    if box, do: Xignal.Store.put(:tuya, :state, box)

    unless :persistent_term.get({__MODULE__, :announced}, false) do
      :persistent_term.put({__MODULE__, :announced}, true)

      CatLitterBox.Ntfy.send(
        "Startet logging, siste veiing: #{CatLitterBox.Cats.weighed(weight)}"
      )
    end

    {:ok, state}
  end

  # The program sends :ping when no message has come for 4 minutes, see CatLitterBox.Logic. A
  # connection can stop delivering without closing, so a ping that has no pong by the next one closes
  # it, and the socket connects again.
  def handle_info(:ping, %{pong: false} = state) do
    log("no pong, reconnecting")
    {:close, state}
  end

  def handle_info(:ping, state), do: {:reply, :ping, %{state | pong: false}}

  @impl WebSockex
  def handle_pong(_frame, state), do: {:ok, %{state | pong: true}}

  @impl WebSockex
  def handle_disconnect(%{reason: reason}, state) do
    log("disconnected: #{inspect(reason)}")
    Process.sleep(5_000)
    {:reconnect, state}
  end

  defp log(text), do: IO.puts("#{DateTime.utc_now() |> DateTime.truncate(:second)} #{text}")

  # A message is JSON in base64 in JSON, with its data encrypted by a part of the secret. Every one is
  # told to the program as the event :activity_notice, which shows the connection is alive.
  @impl WebSockex
  def handle_frame({:text, frame}, state) do
    Xignal.Store.trigger(:tuya, :activity_notice)

    %{"messageId" => id, "payload" => payload, "properties" => %{"em" => mode}} =
      JSON.decode!(frame)

    data = payload |> Base.decode64!() |> JSON.decode!() |> Map.fetch!("data") |> Base.decode64!()
    text = decrypt(mode, data, state.keys.key)
    report = JSON.decode!(text)
    log("report: #{text}")
    values = report["status"] || get_in(report, ["bizData", "properties"]) || []

    # The device reports the weight in units of 100 g, as a number or as text.
    for %{"code" => @code, "value" => units} <- values, units = number(units), units != nil do
      Xignal.Store.put(:tuya, :cat_weight, units * 100)
    end

    for %{"code" => @state, "value" => box} when is_binary(box) <- values do
      Xignal.Store.put(:tuya, :state, box)
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

  # The weight now, in grams, and the state, asked of the REST API. The device's status leaves out the
  # points of its own, as the state; its shadow has them all.
  defp current(keys) do
    token = get("/v1.0/token?grant_type=1", "", keys)["access_token"]
    status = get("/v2.0/cloud/thing/#{@device}/shadow/properties", token, keys)["properties"]
    weight = hd(for %{"code" => @code, "value" => units} <- status, do: units * 100)

    box =
      Enum.find_value(status, fn s ->
        s["code"] == @state and is_binary(s["value"]) and s["value"]
      end)

    {weight, box}
  end

  # A request signed with the secret, as Tuya's API asks. The header names keep their underscores,
  # which Req would turn into dashes in atom names.
  defp get(path, token, keys) do
    sha256 = &Base.encode16(:crypto.hash(:sha256, &1), case: :lower)
    t = Integer.to_string(System.os_time(:millisecond))
    to_sign = [keys.id, token, t, "GET\n", sha256.(""), "\n\n", path]
    sign = Base.encode16(:crypto.mac(:hmac, :sha256, keys.secret, to_sign))
    headers = [{"client_id", keys.id}, {"sign", sign}, {"t", t}, {"sign_method", "HMAC-SHA256"}]
    headers = if token == "", do: headers, else: [{"access_token", token} | headers]

    %{status: 200, body: %{"success" => true, "result" => result}} =
      Req.get!("https://openapi.tuyaeu.com" <> path, headers: headers)

    result
  end

  defp decrypt("aes_gcm", <<iv::binary-12, rest::binary>>, key) do
    size = byte_size(rest) - 16
    <<text::binary-size(^size), tag::binary>> = rest
    :crypto.crypto_one_time_aead(:aes_128_gcm, key, iv, text, "", tag, false)
  end

  defp decrypt(_ecb, data, key) do
    :crypto.crypto_one_time(:aes_128_ecb, key, data, encrypt: false, padding: :pkcs_padding)
  end
end
