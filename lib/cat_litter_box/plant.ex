defmodule CatLitterBox.Plant do
  @moduledoc """
  The program: the store it reads the socket's partition through, the historian, and the wiring.

  The historian logs a row when the weight has changed, and once a day without that, to Arrow files
  in `log/` that are kept for five years, with the quality beside it; and the litter box's state the
  same way, as the series "litter_box".
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
    state = Xignal.Store.input(:cat_logger, :tuya, :state, default: "")

    Xignal.Historian.sink(
      weight,
      Xignal.Historian.output_q(CatLitterBox.History, "cat",
        field: :weight_g,
        min: 0,
        heartbeat: ~t(1d)
      )
    )

    Xignal.Historian.sink(
      state,
      Xignal.Historian.output(CatLitterBox.History, "litter_box",
        field: :state,
        type: :string,
        heartbeat: ~t(1d)
      )
    )

    CatLitterBox.Logic.watch(weight, activity_notice)
    CatLitterBox.Logic.fault(state)
  end
end
