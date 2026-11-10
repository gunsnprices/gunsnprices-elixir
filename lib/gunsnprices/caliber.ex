defmodule GunsNPrices.Caliber do
  @moduledoc """
  A caliber (cartridge) from the GunsNPrices caliber list.

  `id` is stable (`"9x19mmparabellum"`), `name` is the display name (`"9×19mm Parabellum"`), `type` is what it is
  chambered in and `url` is the GunsNPrices page comparing prices for it (`""` if there is none).

  Encodes to JSON (Elixir's `JSON`, and `Jason` when it is installed) with the same fields as the Python and
  JavaScript packages: `{"id": ..., "name": ..., "type": "handgun", "url": ...}`.
  """

  @derive JSON.Encoder
  if Code.ensure_loaded?(Jason.Encoder), do: @derive(Jason.Encoder)
  @enforce_keys [:id, :name, :type]
  defstruct [:id, :name, :type, url: ""]

  @typedoc "What a caliber is chambered in: the `type` field of the GunsNPrices caliber list."
  @type caliber_type :: :handgun | :rifle | :rimfire | :shotgun | :airgun | :muzzleloader

  @type t :: %__MODULE__{id: String.t(), name: String.t(), type: caliber_type(), url: String.t()}
end
