# GunsNPrices

[![Hex.pm](https://img.shields.io/hexpm/v/gunsnprices.svg)](https://hex.pm/packages/gunsnprices)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/gunsnprices)
[![CI](https://github.com/gunsnprices/gunsnprices-elixir/actions/workflows/ci.yml/badge.svg)](https://github.com/gunsnprices/gunsnprices-elixir/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT%20%2B%20CC%20BY%204.0%20data-blue)](#license)

Parse firearm and ammunition product titles into structured data: brand, model, caliber, magazine capacity, barrel
length, rounds per box and cost per round.

```elixir
iex> info = GunsNPrices.parse_title("Glock 19 Gen 5 MOS 9mm 4.02in 15rd Pistol PA195S203MOS")
iex> {info.model.model, info.caliber.name, info.capacity, info.barrel_length}
{"Glock 19 Gen 5 MOS", "9×19mm Parabellum", 15, 4.02}
```

This is the title parser behind [GunsNPrices](https://gunsnprices.com), a price comparison site that tracks 40+ US gun
and ammo stores. Store titles are messy (`G19 GEN5 9MM 15RD FS`, `O/U 12/28 BL/WD 3"`, `Federal 308 150gr ... 20rds`),
and matching the same product across stores starts with reading them reliably. The model dictionaries and the caliber
list in this package are the ones the site uses to group listings, so you get the same model names you see on
[gunsnprices.com](https://gunsnprices.com).

Pure Elixir, no runtime dependencies; the data is compiled into the package. It is a port of the
[Python package](https://pypi.org/project/gunsnprices/) and gives identical results: the test suite checks the same
1,150 recorded store titles as the Python and [JavaScript](https://www.npmjs.com/package/gunsnprices) versions, and it
agrees with Python on all 63,755 titles of the GunsNPrices catalog.

## Installation

Add `gunsnprices` to your dependencies in `mix.exs` (Elixir 1.18 or newer):

```elixir
def deps do
  [
    {:gunsnprices, "~> 0.1"}
  ]
end
```

## What it recognizes

| Field | Example in a title | Result |
|---|---|---|
| Firearm or ammo | `... 150gr ... 20rds` | `:ammo` |
| Brand and model (50 brands) | `G19 Gen5 MOS`, part number `PA195S203` | `Glock 19 Gen 5 MOS` |
| Calibers (293) | `.357 Mag / .38 Spl`, `6.5 CM`, `12ga`, `300 BLK`, `7MM RM` | `.357 Mag`, `.38 S&W Special`, ... |
| Magazine capacity | `15+1`, `17RD`, `13rd/15rd`, `10-shot` | `15`, `17`, `15`, `10` |
| Barrel length, inches | `4.02in`, `16 1/2"`, `22 BBL`, `O/U 12/28` | `4.02`, `16.5`, `22.0`, `28.0` |
| Rounds per box | `50/Box`, `Box of 20`, `1,000 Rounds`, `20/25` | `50`, `20`, `1000`, `20` |
| Cost per round | price `449.99` + `1000 Rounds` | `0.45` |

Brands with model dictionaries: Barrett, Benelli, Beretta, Bergara, Browning, Cadex, Canik, Charles Daly, Chiappa,
Christensen Arms, Cimarron, CMMG, Colt, CVA, CZ, Daniel Defense, Desert Eagle, Diamondback, Fierce, FN, Glock,
Great Lakes, Henry, Heritage, HK, Howa, Kel-Tec, Kimber, Kriss, Marlin, Mossberg, Remington, Retay, Rossi, Ruger, Savage,
SCCY, Seekins, Shadow Systems, Sig Sauer, Smith & Wesson, Springfield, Stevens, Stoeger, Taurus, Tikka, Tristar, Walther,
Weatherby, Winchester.

## Usage

### Everything at once

```elixir
iex> ammo = GunsNPrices.parse_title("Federal American Eagle 5.56x45mm 55gr FMJ 1000 Rounds", price: 449.99)
iex> {ammo.kind, ammo.caliber.name, ammo.rounds, ammo.cost_per_round}
{:ammo, "5.56×45mm NATO", 1000, 0.45}
```

`parse_title(title, opts \\ [])` returns a `%GunsNPrices.ProductInfo{}`:

| Field | Type | Notes |
|---|---|---|
| `kind` | `:firearm \| :ammo` | pass `kind:` to skip the guess |
| `brand` | `String.t()` | brand of the identified model, else the `brand:` you passed, else `""` |
| `model` | `%GunsNPrices.ModelMatch{} \| nil` | firearms only |
| `caliber` | `%GunsNPrices.Caliber{} \| nil` | first caliber in the title |
| `calibers` | `[%GunsNPrices.Caliber{}]` | all calibers, in order |
| `capacity` | `pos_integer() \| nil` | magazine capacity (for `15+1` it is 15), firearms only |
| `barrel_length` | `float() \| nil` | inches, firearms only |
| `rounds` | `pos_integer() \| nil` | rounds per box, ammo only |
| `cost_per_round` | `float() \| nil` | ammo with `price:` only |

Options: `brand:` (the manufacturer field from a feed, which helps with titles that don't name the brand), `mpn:`,
`sku:`, `price:` and `kind:`. With the part number it decodes Glock models when the title says nothing useful:

```elixir
iex> GunsNPrices.identify_model("GLOCK 9MM PISTOL 15RD", brand: "Glock", mpn: "UA4350201")
%GunsNPrices.ModelMatch{
  brand: "Glock",
  family: "Glock 43",
  model: "Glock 43",
  generation: "",
  configs: [],
  features: [],
  source: :mpn
}
```

The result structs encode to JSON (Elixir's built-in `JSON`, and `Jason` when your application uses it) with the same
field names as the Python and JavaScript packages:

```elixir
GunsNPrices.parse_title("Hornady 6.5 CM 140gr ELD Match 20rds") |> JSON.encode!() |> IO.puts()
```

```json
{"title":"Hornady 6.5 CM 140gr ELD Match 20rds","kind":"ammo","brand":"","model":null,"caliber":{"id":"6-5mmcreedmoor","name":"6.5mm Creedmoor","type":"rifle","url":"https://gunsnprices.com/ammo/rifle-ammo/6-5mm-creedmoor"},"calibers":[{"id":"6-5mmcreedmoor","name":"6.5mm Creedmoor","type":"rifle","url":"https://gunsnprices.com/ammo/rifle-ammo/6-5mm-creedmoor"}],"capacity":null,"barrel_length":null,"rounds":20,"cost_per_round":null}
```

### Models

```elixir
iex> m = GunsNPrices.identify_model(~s(Sig Sauer P365 XL 9mm 3.7" 12+1 Optic Ready))
iex> {m.family, m.model}
{"Sig Sauer P365", "Sig Sauer P365 XL"}
iex> GunsNPrices.identify_model("Glock 19 holster")
nil
iex> GunsNPrices.identify_model("Umarex Glock 19 CO2 BB pistol")
nil
```

A `%GunsNPrices.ModelMatch{}` has `brand`, `family`, `model` (the most specific name), `generation`, `configs` (such as
`MOS`, `Compact`), `features` (such as `Threaded Barrel`, `FDE`) and `source` (`:title` or `:mpn`). Accessories, parts,
airguns and airsoft are rejected. `list_brands/0` returns the 50 brands.

### Calibers

```elixir
iex> GunsNPrices.find_calibers("Henry Big Boy .44 Mag/.44 Spl 20in") |> Enum.map(& &1.name)
[".44 Magnum", ".44 S&W Special"]
iex> GunsNPrices.normalize_caliber("308 WIN (7.62X51 NATO)")
%GunsNPrices.Caliber{
  id: "308win",
  name: ".308 Win",
  type: :rifle,
  url: "https://gunsnprices.com/ammo/rifle-ammo/308-win"
}
```

Each `%GunsNPrices.Caliber{}` has a stable `id`, a display `name`, a `type` (`:handgun`, `:rifle`, `:rimfire`,
`:shotgun`, `:airgun`, `:muzzleloader`) and the `url` of its GunsNPrices price comparison page. `normalize_caliber/1`
is meant for caliber fields in product feeds; `find_calibers/1` searches free text. `list_calibers/0` returns all 293
and `caliber_by_id/1` looks one up.

### Numbers

```elixir
iex> GunsNPrices.magazine_capacity("Springfield Hellcat Pro OSP 9mm 3.7in 15rd/17rd")
17
iex> GunsNPrices.barrel_length(~s(Mossberg 590 Persuader 12/20 BL/SY 3"))  # 3" is the chamber
20.0
iex> GunsNPrices.rounds_per_box("Winchester 308 150gr PowerMax Bonded 20rds")
20
iex> GunsNPrices.cost_per_round(31.99, 20)
1.5995
```

## Performance

The rules are compiled on the first call (under 0.1 s) and kept in `:persistent_term`; call `GunsNPrices.warm_up/0`
from your application's `start/2` to pay that at boot. After that `parse_title/2` takes about 0.6 ms per title on one
core (Apple M-series, OTP 29). Every function is pure and can be called from any number of processes at once.

## How it matches Python

The rules are written for Python's `re` module. Erlang's `:re` (PCRE2) runs them after a small translation, so they
match exactly the way Python does: `\w`, `\s` and `\d` follow Python's Unicode definitions, case-insensitive `i` also
matches `ı` and `İ` (Turkish brand names), word boundaries next to combining marks are handled, and `lower()`,
`html.unescape()` and `round()` behave like Python's. Characters assigned after Unicode 15.1 (Python 3.13's version)
may be classified differently; they don't occur in store titles.

## Accuracy

Measured with the reference implementation on 50,202 firearm and 13,555 ammunition listings from 40+ stores on
gunsnprices.com (October 2026), against the attributes stored on the site:

| What | Found in the title | Right when found |
|---|---|---|
| Model (32,317 listings with a known model) | 99.97% | 99.8% same name as the site |
| Caliber, firearms | 81% | 97.8% |
| Caliber, ammo | 91% | 94.9% |
| Magazine capacity | 46% | 95.6% |
| Barrel length | 58% | 94.4% |
| Rounds per box | 80% | 96.6% |

"Found" is limited by the titles themselves: many stores don't put the caliber or barrel length in the title at all.
Most of the "wrong" cases we checked by hand are errors in the store data, not in the parser.

## Data

The model dictionaries and caliber list ship inside the package (`priv/data/*.json`, the same files as the Python
package, read when the package is compiled). The same data, with listing counts and price levels, is published as open
datasets:

- Hugging Face: [gunsnprices/firearm-calibers](https://huggingface.co/datasets/gunsnprices/firearm-calibers),
  [gunsnprices/firearm-models](https://huggingface.co/datasets/gunsnprices/firearm-models)
- GitHub: [gunsnprices/firearm-datasets](https://github.com/gunsnprices/firearm-datasets)
- MCP server for AI assistants, built on the same parser: [gunsnprices-mcp](https://github.com/gunsnprices/gunsnprices-mcp)

## Limitations

- Titles from US retailers, in English.
- Models are covered for the 50 brands above. Other brands still get calibers and numbers.
- Built for firearms and ammunition. Magazines, parts and accessories get calibers and numbers but no model.

## License

The code is under the [MIT License](LICENSE). The model and caliber data in `priv/data/` is under
[CC BY 4.0](LICENSE-DATA): you can use it for anything, including commercial use, if you credit
**GunsNPrices (gunsnprices.com)** with a link.

Questions, corrections and missing models: open an issue or write to app@gunsnprices.com.
Current gun and ammo prices: [gunsnprices.com](https://gunsnprices.com).
