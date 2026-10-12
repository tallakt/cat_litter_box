defmodule CatLitterBox.Plant do
  @moduledoc """
  The program: the store it reads the socket's partition through, the historian, and the wiring.

  The historian logs a row when the weight has changed, and once a day without that, to Arrow files
  in `log/` that are kept for five years, with the quality beside it.
  """

  use Xignal.Program, interval: ~t(1s)

  def devices do
    [
      {Xignal.Store, name: :cat_logger},
      {Xignal.Historian,
       name: CatLitterBox.History,
       backend: {Xignal.Historian.Arrow, dir: "log", expiry: 5 * 365 * ~t(1d)},
       flush: ~t(10s)}
    ]
  end

  def wire do
    weight = Xignal.Store.input_q(:cat_logger, :tuya, :cat_weight, default: 0)
    activity_notice = Xignal.Store.fired(:cat_logger, :tuya, :activity_notice)

    Xignal.Historian.sink(
      weight,
      Xignal.Historian.output_q(CatLitterBox.History, "cat",
        field: :weight_g,
        min: 0,
        heartbeat: ~t(1d)
      )
    )

    CatLitterBox.Logic.watch(weight, activity_notice)
  end
end
