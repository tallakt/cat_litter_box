defmodule CatLitterBox.TuyaStore do
  @moduledoc """
  The store's `:tuya` partition, which the socket writes, with its points declared. A partition
  takes no new points once it has started, so they are declared here, once for each start of the
  partition, and not by the socket, which may start many times.
  """

  use Supervisor

  def start_link(opts), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl Supervisor
  def init(_opts) do
    children = [{Xignal.Store, name: :tuya}, __MODULE__.Points]
    Supervisor.init(children, strategy: :rest_for_one)
  end

  defmodule Points do
    @moduledoc false
    use GenServer

    def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

    @impl GenServer
    def init(_opts) do
      Xignal.Store.output(:tuya, :cat_weight, default: 0, desc: "Cat weight, g")
      Xignal.Store.output(:tuya, :state, default: "", desc: "What the litter box is doing")
      Xignal.Store.event(:tuya, :activity_notice, desc: "A Tuya message")
      Xignal.Store.start(:tuya)
      {:ok, nil}
    end
  end
end
