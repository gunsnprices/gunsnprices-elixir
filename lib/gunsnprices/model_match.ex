defmodule GunsNPrices.ModelMatch do
  @moduledoc """
  Result of `GunsNPrices.identify_model/2`.

    * `brand` - brand as named on GunsNPrices, e.g. `"Glock"`
    * `family` - model family, e.g. `"Glock 19"`
    * `model` - most specific model, e.g. `"Glock 19 Gen 5 MOS"`
    * `generation` - `"5"`, `"V"`, `"V3"` ... or `""` when unknown
    * `configs` - configurations found, e.g. `["MOS"]`, `["Compact"]`
    * `features` - features found, e.g. `["Threaded Barrel", "FDE"]`
    * `source` - `:title` (named in the title) or `:mpn` (decoded from a Glock part number)
  """

  @derive JSON.Encoder
  if Code.ensure_loaded?(Jason.Encoder), do: @derive(Jason.Encoder)
  @enforce_keys [:brand, :family, :model]
  defstruct [:brand, :family, :model, generation: "", configs: [], features: [], source: :title]

  @type t :: %__MODULE__{
          brand: String.t(),
          family: String.t(),
          model: String.t(),
          generation: String.t(),
          configs: [String.t()],
          features: [String.t()],
          source: :title | :mpn
        }
end
