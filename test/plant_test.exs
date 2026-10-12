defmodule CatLitterBox.PlantTest do
  use ExUnit.Case

  test "the program reads the weight and the socket's messages, and logs the weight" do
    io = for row <- Xignal.Program.io_list(CatLitterBox.Plant), do: {row.dir, row.address}

    assert io == [
             {:input, "tuya.activity_notice"},
             {:input, "tuya.cat_weight"},
             {:output, "cat weight_g"}
           ]
  end
end
