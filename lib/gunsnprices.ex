defmodule GunsNPrices do
  @moduledoc """
  Parse firearm and ammunition product titles into structured data: brand, model, caliber, magazine capacity, barrel
  length, rounds per box and cost per round.

      iex> info = GunsNPrices.parse_title("Glock 19 Gen 5 MOS 9mm 4.02in 15rd Pistol PA195S203MOS")
      iex> {info.model.model, info.caliber.name, info.capacity, info.barrel_length}
      {"Glock 19 Gen 5 MOS", "9×19mm Parabellum", 15, 4.02}

  This is the title parser behind [GunsNPrices](https://gunsnprices.com), a price comparison site that tracks 40+ US
  gun and ammo stores. Store titles are messy (`G19 GEN5 9MM 15RD FS`, `O/U 12/28 BL/WD 3"`,
  `Federal 308 150gr ... 20rds`), and matching the same product across stores starts with reading them reliably. The
  model dictionaries (50 brands) and the caliber list (293 calibers) compiled into this package are the ones the site
  uses to group listings, so you get the same model names you see on gunsnprices.com.

  It is a port of the [Python package](https://pypi.org/project/gunsnprices/) and gives the same results: the test
  suite checks 1,150 recorded store titles against the Python output.

  ## What it recognizes

  | Field | Example in a title | Result |
  |---|---|---|
  | Firearm or ammo | `... 150gr ... 20rds` | `:ammo` |
  | Brand and model | `G19 Gen5 MOS`, part number `PA195S203` | `Glock 19 Gen 5 MOS` |
  | Calibers | `.357 Mag / .38 Spl`, `6.5 CM`, `12ga`, `300 BLK`, `7MM RM` | `.357 Mag`, `.38 S&W Special`, ... |
  | Magazine capacity | `15+1`, `17RD`, `13rd/15rd`, `10-shot` | `15`, `17`, `15`, `10` |
  | Barrel length, inches | `4.02in`, `16 1/2"`, `22 BBL`, `O/U 12/28` | `4.02`, `16.5`, `22.0`, `28.0` |
  | Rounds per box | `50/Box`, `Box of 20`, `1,000 Rounds`, `20/25` | `50`, `20`, `1000`, `20` |
  | Cost per round | price `449.99` + `1000 Rounds` | `0.45` |

  ## Performance

  The data is compiled into the package; the rules are compiled on first use (a fraction of a second, see
  `warm_up/0`) and kept in `:persistent_term`. All functions are pure and can be called from any process.

  ## Data license

  The code is MIT. The model dictionaries and caliber list (`priv/data/*.json`) are © GunsNPrices, licensed under
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/): credit "GunsNPrices (gunsnprices.com)" with a link to
  <https://gunsnprices.com> if you redistribute them.
  """

  alias GunsNPrices.{Caliber, Calibers, ModelMatch, Models, ProductInfo, Specs}

  @version Mix.Project.config()[:version]

  @typedoc """
  What you know about a listing besides its title (all optional):

    * `:brand` - manufacturer (helps with titles that don't name the brand)
    * `:mpn` - manufacturer part number (Glock part numbers encode the model and generation)
    * `:sku` - store SKU
    * `:price` - price of the listing; with ammo it gives the cost per round
    * `:kind` - `:firearm` or `:ammo` (also `"firearm"` / `"ammo"`); guessed from the title when not given
  """
  @type option ::
          {:brand, String.t() | nil}
          | {:mpn, String.t() | nil}
          | {:sku, String.t() | nil}
          | {:price, number() | nil}
          | {:kind, :firearm | :ammo | String.t() | nil}

  @doc "Version of this package."
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Parse a product title into brand, model, caliber, capacity, barrel length, rounds per box and cost per round.

  The kind (firearm or ammo) is guessed from the title unless the `:kind` option is given. Firearms get `model`,
  `capacity` and `barrel_length`; ammunition gets `rounds` and, with the `:price` option, `cost_per_round`.

      iex> info = GunsNPrices.parse_title("Federal American Eagle 9mm Luger 115gr FMJ, 50/Box", price: 18.99)
      iex> {info.kind, info.caliber.id, info.rounds, info.cost_per_round}
      {:ammo, "9x19mmparabellum", 50, 0.3798}
  """
  @spec parse_title(String.t() | nil, [option()]) :: ProductInfo.t()
  def parse_title(title, opts \\ []) do
    title = text(title)
    opts = options(opts)

    kind =
      case opts[:kind] do
        nil -> if Specs.looks_like_ammo?(title), do: :ammo, else: :firearm
        kind -> kind
      end

    calibers = Calibers.find_calibers(title)

    info = %ProductInfo{
      title: title,
      kind: kind,
      brand: opts[:brand] || "",
      caliber: List.first(calibers),
      calibers: calibers
    }

    case kind do
      :ammo ->
        rounds = Specs.rounds_per_box(title)
        price = opts[:price]
        %{info | rounds: rounds, cost_per_round: if(price, do: Specs.cost_per_round(price, rounds))}

      :firearm ->
        model = Models.identify_model(title, opts)

        %{
          info
          | model: model,
            brand: if(model, do: model.brand, else: info.brand),
            capacity: Specs.magazine_capacity(title),
            barrel_length: Specs.barrel_length(title)
        }
    end
  end

  @doc """
  Find the brand, model family and model in a firearm product title.

  Returns `nil` when no covered brand/model is recognized. Only firearms are covered: titles of accessories, parts and
  airguns return `nil`. Takes the `:brand`, `:mpn` and `:sku` options (see `t:option/0`); with the part number it
  decodes Glock models when the title says nothing useful.

      iex> m = GunsNPrices.identify_model("Glock 19 Gen 5 MOS 9mm 4.02in 15rd Pistol PA195S203MOS")
      iex> {m.family, m.model, m.generation, m.configs}
      {"Glock 19", "Glock 19 Gen 5 MOS", "5", ["MOS"]}
      iex> GunsNPrices.identify_model("GLOCK 9MM PISTOL 15RD", brand: "Glock", mpn: "UA4350201").model
      "Glock 43"
      iex> GunsNPrices.identify_model("Glock 19 holster")
      nil
  """
  @spec identify_model(String.t() | nil, [option()]) :: ModelMatch.t() | nil
  def identify_model(title, opts \\ []), do: Models.identify_model(text(title), options(opts))

  @doc """
  Brands covered by the model dictionaries, in dictionary order.

      iex> brands = GunsNPrices.list_brands()
      iex> {length(brands), "Glock" in brands}
      {50, true}
  """
  @spec list_brands() :: [String.t()]
  def list_brands, do: Models.list_brands()

  @doc """
  All calibers mentioned in `text`, in order of appearance, without duplicates.

      iex> GunsNPrices.find_calibers("Ruger GP100 .357 Mag / .38 Special 4.2in Revolver") |> Enum.map(& &1.name)
      [".357 Mag", ".38 S&W Special"]
  """
  @spec find_calibers(String.t() | nil) :: [Caliber.t()]
  def find_calibers(text), do: Calibers.find_calibers(text(text))

  @doc """
  The first caliber mentioned in `text`, or `nil`.

      iex> GunsNPrices.find_caliber("Hornady 6.5 CM 140gr ELD Match").id
      "6-5mmcreedmoor"
  """
  @spec find_caliber(String.t() | nil) :: Caliber.t() | nil
  def find_caliber(text), do: Calibers.find_caliber(text(text))

  @doc """
  Normalize a caliber field ("9mm Luger", "5.56 NATO", "12 GA") to a `GunsNPrices.Caliber`.

  The whole value is looked up first; if it isn't a known spelling, the first caliber found inside it is returned.

      iex> c = GunsNPrices.normalize_caliber("308 WIN (7.62X51 NATO)")
      iex> {c.id, c.name, c.type}
      {"308win", ".308 Win", :rifle}
  """
  @spec normalize_caliber(String.t() | nil) :: Caliber.t() | nil
  def normalize_caliber(value), do: Calibers.normalize_caliber(text(value))

  @doc """
  The full caliber list (293 calibers), sorted by name.
  """
  @spec list_calibers() :: [Caliber.t()]
  def list_calibers, do: Calibers.list_calibers()

  @doc """
  The caliber with this id, or `nil`.

      iex> GunsNPrices.caliber_by_id("12gauge").name
      "12 Gauge"
  """
  @spec caliber_by_id(String.t()) :: Caliber.t() | nil
  def caliber_by_id(id), do: Calibers.caliber_by_id(id)

  @doc """
  Magazine capacity of a firearm or magazine from its title ("17RD", "15+1", "10-shot"), or `nil`.

  For "15+1" the magazine capacity (15) is returned; with two magazine sizes ("13rd/15rd") the larger one. Use it on
  firearm and magazine titles: in ammunition titles "20 rounds" means rounds per box (see `rounds_per_box/1`).

      iex> GunsNPrices.magazine_capacity("Glock 19 Gen5 9mm 4.02in 15+1 Black")
      15
  """
  @spec magazine_capacity(String.t() | nil) :: pos_integer() | nil
  def magazine_capacity(title), do: Specs.magazine_capacity(text(title))

  @doc """
  Barrel length in inches from a firearm title (`4.25"`, "16 in", "20-inch", `16 1/2"`, "22 BBL"), or `nil`.

  Chamber length (3" on shotguns), twist rate, handguard and length-of-pull values are skipped.

      iex> GunsNPrices.barrel_length("Ruger GP100 .357 Mag 4.2in Revolver")
      4.2
      iex> GunsNPrices.barrel_length(~s(Mossberg 590 Persuader 12/20 BL/SY 3"))
      20.0
  """
  @spec barrel_length(String.t() | nil) :: float() | nil
  def barrel_length(title), do: Specs.barrel_length(text(title))

  @doc """
  Number of rounds in one package of ammunition ("20rds", "50/box", "Box of 25", "1,000 Rounds"), or `nil`.

      iex> GunsNPrices.rounds_per_box("Federal American Eagle 9mm 115gr FMJ, 50/Box")
      50
  """
  @spec rounds_per_box(String.t() | nil) :: pos_integer() | nil
  def rounds_per_box(title), do: Specs.rounds_per_box(text(title))

  @doc """
  Price of one round, rounded to 4 decimals (half to even, like Python), or `nil` without a price or a round count.

      iex> GunsNPrices.cost_per_round(18.99, 50)
      0.3798
  """
  @spec cost_per_round(number() | nil, integer() | nil) :: float() | nil
  def cost_per_round(price, rounds), do: Specs.cost_per_round(price, rounds)

  @doc """
  True if the title reads like ammunition (bullet weight, "ammo", "20/box", ...) rather than a firearm.

      iex> GunsNPrices.looks_like_ammo?("Winchester 308 150gr PowerMax Bonded 20rds")
      true
  """
  @spec looks_like_ammo?(String.t() | nil) :: boolean()
  def looks_like_ammo?(title), do: Specs.looks_like_ammo?(text(title))

  @doc """
  Compile all rules now instead of on first use (for example in your application's `start/2`).
  """
  @spec warm_up() :: :ok
  def warm_up do
    _ = parse_title("Glock 19 Gen 5 9mm 15rd Pistol")
    _ = parse_title("Federal 9mm 115gr FMJ 50/Box")
    :ok
  end

  # Titles are text: nil reads as "" and invalid UTF-8 bytes become U+FFFD.
  defp text(nil), do: ""
  defp text(s) when is_binary(s), do: if(String.valid?(s), do: s, else: String.replace_invalid(s))

  # Empty strings and a zero price count as "not given", like falsy values in the reference implementation.
  defp options(opts) do
    opts = Keyword.validate!(opts, [:brand, :mpn, :sku, :price, :kind])

    [
      brand: blank(opts[:brand]),
      mpn: blank(opts[:mpn]),
      sku: blank(opts[:sku]),
      price: if(opts[:price] in [nil, 0, +0.0, -0.0], do: nil, else: opts[:price]),
      kind: kind(opts[:kind])
    ]
  end

  defp blank(v) when v in [nil, ""], do: nil
  defp blank(v) when is_binary(v), do: text(v)

  defp kind(nil), do: nil
  defp kind(k) when k in [:firearm, "firearm"], do: :firearm
  defp kind(k) when k in [:ammo, "ammo"], do: :ammo
  defp kind(k), do: raise(ArgumentError, "unknown kind #{inspect(k)} (expected :firearm or :ammo)")
end
