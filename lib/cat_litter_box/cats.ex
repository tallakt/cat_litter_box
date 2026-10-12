defmodule CatLitterBox.Cats do
  @moduledoc """
  Which of the three cats a weight is, by weight alone. The weigh-ins of 6 to 12 October 2026 fell in
  three groups, 4.47, 4.97 and 5.71 kg on average, each about 0.17 kg apart around it; the bounds are
  halfway between. Prins and Bamse overlap, so 4.7 or 4.8 kg is now and then the other one. Less
  than 4 kg is a cat partly on the scale.
  """

  def weighed(grams) when grams < 4000, do: "For lett for å bestemme hvem (#{kg(grams)})"
  def weighed(grams) when grams < 4750, do: "Prins #{kg(grams)}"
  def weighed(grams) when grams < 5350, do: "Bamse #{kg(grams)}"
  def weighed(grams), do: "Diva #{kg(grams)}"

  defp kg(grams) do
    String.replace(:erlang.float_to_binary(grams / 1000, decimals: 1), ".", ",") <> " kg"
  end
end
