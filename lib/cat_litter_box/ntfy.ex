defmodule CatLitterBox.Ntfy do
  @moduledoc """
  A push notification to this topic on ntfy.sh, which the ntfy app subscribes to. The topic name is
  the only secret. Each is sent from its own process, so that the scan never waits for the network.
  """

  @url "https://ntfy.sh/kattedo-53d05ded1cab7a1e6e5dcd3184a327c9"

  def send(message) do
    Task.start(fn ->
      %{status: 200} = Req.post!(@url, body: message, headers: [{"title", "Kattedo"}])
    end)
  end
end
