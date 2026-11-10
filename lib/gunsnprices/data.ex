defmodule GunsNPrices.Data do
  @moduledoc false
  # The model dictionaries, the caliber list and the HTML entity table, read from priv/data/*.json when the package is
  # compiled and stored in the module as literals. JSON objects are read in order: the order of rewrite rules,
  # configurations, features and generations matters, like in the reference implementation (Python dicts keep it).

  @data_dir Path.expand("../../priv/data", __DIR__)
  @models_file Path.join(@data_dir, "models.json")
  @calibers_file Path.join(@data_dir, "calibers.json")
  @entities_file Path.join(@data_dir, "entities.json")
  @external_resource @models_file
  @external_resource @calibers_file
  @external_resource @entities_file

  decode = fn file ->
    {value, :ok, ""} =
      file
      |> File.read!()
      |> JSON.decode(:ok,
        object_push: fn k, v, acc -> [{k, v} | acc] end,
        object_finish: fn acc, old -> {{:obj, Enum.reverse(acc)}, old} end
      )

    value
  end

  get = fn {:obj, pairs}, key, default ->
    case List.keyfind(pairs, key, 0) do
      {_, nil} -> default
      {_, v} -> v
      nil -> default
    end
  end

  pairs = fn
    {:obj, p} -> p
    _ -> []
  end

  plain = fn plain, v ->
    case v do
      {:obj, p} -> Map.new(p, fn {k, x} -> {k, plain.(plain, x)} end)
      l when is_list(l) -> Enum.map(l, &plain.(plain, &1))
      x -> x
    end
  end

  load_dict = fn d ->
    terms? = get.(d, "mode", nil) == "terms"
    models = get.(d, "models", nil)

    %{
      brand: get.(d, "brand", ""),
      brand_word: get.(d, "brand_word", ""),
      brand_rx: get.(d, "brand_rx", ""),
      terms?: terms?,
      title_rewrite: pairs.(get.(d, "title_rewrite", nil)),
      exclude: get.(d, "exclude", []),
      exclude_soft: get.(d, "exclude_soft", []),
      other_brand_block: get.(d, "other_brand_block", []),
      configs: pairs.(get.(d, "configs", nil)),
      features: pairs.(get.(d, "features", nil)),
      gens: pairs.(get.(d, "gens", nil)),
      brand_names: get.(d, "brand_names", []),
      deny_brand_names: get.(d, "deny_brand_names", []),
      family_display: plain.(plain, get.(d, "family_display", {:obj, []})),
      other_brand_models: get.(d, "other_brand_models", []),
      needed: plain.(plain, get.(d, "needed", {:obj, []})),
      feature_order: get.(d, "feature_order", []),
      implied: plain.(plain, get.(d, "config_implied_by_gen_family", {:obj, []})),
      terms:
        if terms? do
          for m <- models do
            %{
              name: get.(m, "name", ""),
              family: get.(m, "family", ""),
              match: get.(m, "match", ""),
              not: get.(m, "not", ""),
              configs: get.(m, "configs", []),
              implied_configs: get.(m, "implied_configs", [])
            }
          end
        else
          []
        end,
      codes: if(terms?, do: %{}, else: plain.(plain, models)),
      bare_model_tokens: get.(d, "bare_model_tokens", []),
      mpn_model_alias: plain.(plain, get.(d, "mpn_model_alias", {:obj, []})),
      mpn_letter_model: plain.(plain, get.(d, "mpn_letter_model", {:obj, []})),
      mpn_letter_gen: plain.(plain, get.(d, "mpn_letter_gen", {:obj, []})),
      no_gen_models: get.(d, "no_gen_models", [])
    }
  end

  @dicts @models_file |> decode.() |> get.("dicts", []) |> Enum.map(load_dict)

  @calibers (for c <- @calibers_file |> decode.() |> get.("calibers", []) do
               %{
                 id: get.(c, "id", ""),
                 name: get.(c, "name", ""),
                 type: c |> get.("type", "") |> String.to_atom(),
                 url: get.(c, "url", "") || "",
                 site_name: get.(c, "site_name", ""),
                 aliases: get.(c, "aliases", []),
                 n: get.(c, "n", 0)
               }
             end)

  entities = plain.(plain, decode.(@entities_file))

  @entities %{
    html5: entities["html5"],
    invalid_charrefs: Map.new(entities["invalid_charrefs"], fn {k, v} -> {String.to_integer(k), v} end),
    invalid_codepoints: MapSet.new(entities["invalid_codepoints"])
  }

  def dicts, do: @dicts
  def calibers, do: @calibers
  def entities, do: @entities
end
