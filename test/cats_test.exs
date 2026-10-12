defmodule CatLitterBox.CatsTest do
  use ExUnit.Case, async: true

  alias CatLitterBox.Cats

  test "each weight names the cat, in Norwegian with a decimal comma" do
    assert Cats.weighed(1800) == "For lett for å bestemme hvem (1,8 kg)"
    assert Cats.weighed(4200) == "Prins 4,2 kg"
    assert Cats.weighed(4700) == "Prins 4,7 kg"
    assert Cats.weighed(4800) == "Bamse 4,8 kg"
    assert Cats.weighed(5300) == "Bamse 5,3 kg"
    assert Cats.weighed(5400) == "Diva 5,4 kg"
  end
end
