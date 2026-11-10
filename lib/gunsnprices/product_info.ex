defmodule GunsNPrices.ProductInfo do
  @moduledoc """
  Result of `GunsNPrices.parse_title/2`. Fields that don't apply or weren't found are `nil` (or empty).

    * `title` - the title as given
    * `kind` - `:firearm` or `:ammo`
    * `brand` - brand of the identified model, else the `:brand` option, else `""`
    * `model` - a `GunsNPrices.ModelMatch`, firearms only
    * `caliber` - first caliber in the title (`GunsNPrices.Caliber`)
    * `calibers` - every caliber in the title (".357 Mag / .38 Special"), in order
    * `capacity` - magazine capacity, firearms only (for "15+1" it is 15)
    * `barrel_length` - barrel length in inches (float), firearms only
    * `rounds` - rounds per box, ammo only
    * `cost_per_round` - price per round, ammo only; needs the `:price` option

  Encodes to JSON with the same field names as the Python and JavaScript packages.
  """

  @derive JSON.Encoder
  if Code.ensure_loaded?(Jason.Encoder), do: @derive(Jason.Encoder)
  @enforce_keys [:title, :kind]
  defstruct [
    :title,
    :kind,
    brand: "",
    model: nil,
    caliber: nil,
    calibers: [],
    capacity: nil,
    barrel_length: nil,
    rounds: nil,
    cost_per_round: nil
  ]

  @type t :: %__MODULE__{
          title: String.t(),
          kind: :firearm | :ammo,
          brand: String.t(),
          model: GunsNPrices.ModelMatch.t() | nil,
          caliber: GunsNPrices.Caliber.t() | nil,
          calibers: [GunsNPrices.Caliber.t()],
          capacity: pos_integer() | nil,
          barrel_length: float() | nil,
          rounds: pos_integer() | nil,
          cost_per_round: float() | nil
        }
end
