defmodule CatLitterBox.Application do
  @moduledoc false

  use Application

  # The socket's partition first, then the program that reads it, then the socket: rest_for_one
  # starts the socket again after either of the others.
  @impl true
  def start(_type, _args) do
    children = [
      CatLitterBox.TuyaStore,
      CatLitterBox.Plant,
      CatLitterBox.Tuya
    ]

    Supervisor.start_link(children, strategy: :rest_for_one, name: CatLitterBox.Supervisor)
  end
end
