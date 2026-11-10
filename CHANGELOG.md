# Changelog

## 0.1.0 (2026-11-10)

First release. Elixir port of the [gunsnprices](https://pypi.org/project/gunsnprices/) Python package 0.1.2, with
identical results on the 1,150 recorded store titles of its test suite and on all 63,755 titles of the GunsNPrices
catalog.

- `GunsNPrices.parse_title/2`: firearm or ammo, brand, model, calibers, magazine capacity, barrel length, rounds per
  box, cost per round (options `brand:`, `mpn:`, `sku:`, `price:`, `kind:`).
- `GunsNPrices.identify_model/2`: 50 brands, the same model dictionaries that [GunsNPrices](https://gunsnprices.com)
  uses on its site; decodes Glock part numbers. `list_brands/0`.
- `find_calibers/1`, `find_caliber/1`, `normalize_caliber/1`, `list_calibers/0`, `caliber_by_id/1`: 293 calibers with
  retailer spellings.
- `magazine_capacity/1`, `barrel_length/1`, `rounds_per_box/1`, `cost_per_round/2`, `looks_like_ammo?/1`.
- Result structs `GunsNPrices.ProductInfo`, `GunsNPrices.ModelMatch`, `GunsNPrices.Caliber` encode to JSON (built-in
  `JSON`; `Jason` too when it is present) with the Python package's field names.
- Pure Elixir on Erlang's `:re`, no runtime dependencies; the data is compiled in, the rules are compiled on first use
  (or `warm_up/0`) and kept in `:persistent_term`. Requires Elixir 1.18+.
