defmodule GunsNPrices.Models do
  @moduledoc false
  # Identify the firearm model in a product title: brand -> family -> model. The rules are GunsNPrices' hand-built
  # model dictionaries (50 brands), the same rules that assign models to listings on gunsnprices.com.

  alias GunsNPrices.{Data, ModelMatch, Py}

  # ---------- compiled rules ----------

  defp state do
    case :persistent_term.get({__MODULE__, :state}, nil) do
      nil ->
        st = %{shared: shared_rules(), dicts: Enum.map(Data.dicts(), &compile_dict/1)}
        :persistent_term.put({__MODULE__, :state}, st)
        st

      st ->
        st
    end
  end

  defp shared_rules do
    ci = &Py.compile(&1, true)
    c = &Py.compile(&1, false)

    %{
      # airguns and airsoft are not firearms (the site filters them by category; here we go by the title)
      airgun:
        ci.(
          ~S"\bair\s*-?\s*(?:gun|rifle|pistol)s?\b|\bairgun|\bairsoft|\bbb\s*(?:gun|pistol|rifle)|\bpellets?\b|\bco2\b"
        ),
      # accessories named after a gun ("Glock 19 holster", "Sig P365 XL 12rd Magazine", "Magpul PMAG for Glock 19").
      # A title that describes a gun (pistol/rifle/..., "15+1", a barrel length) or mentions the item as included
      # ("w/ 3 magazines", "no magazine") is not an accessory.
      acc_noun:
        c.(
          ~S"\b(?:holsters?|magazines?(?!\s*(?:pattern|compatible|well|release|disconnect|safety|catch|cut|tube|extension|fed)\b)|pmags?|slings?|" <>
            ~S"grip panels?|scope mounts?|recoil pads?|speed ?loaders?|mag(?:azine)? loaders?|cleaning kits?|pouch(?:es)?|snap caps?|replacement barrels?|" <>
            ~S"conversion kits?|parts kits?)\b"
        ),
      acc_included:
        c.(
          ~S"(?:(?:\bw/|\bwith\b|\bwithout\b|\bno\b|\band\b|&|\+|\bincl\w*|\bplus\b|\(\d\)|\b[1-9]\b|\btwo\b|\bthree\b|\bfour\b|,|\bor\b|\bextra\b|" <>
            ~S"\bspare\b|\bfactory\b|\bfits\b|\btakes\b|\baccepts\b|\buses\b)[^,]{0,14}|/\s*)$"
        ),
      gun_words:
        c.(
          ~S"\b(?:pistol|rifle|shotgun|revolver|handgun|carbine|firearm|semi-?auto(?:matic)?|bolt[- ]?action|pump|lever[- ]?action|single[- ]?shot|" <>
            ~S'o/u|over/under|sxs|sbr|derringer)\b|\d+\+1\b|\d+(?:\.\d+)?\s*-?\s*(?:"|in\b|inch)'
        ),
      gen: c.(~S"\bgen(?:eration)?\.?\s*-?\s*([1-6])\b|\b([1-6])(?:st|nd|rd|th)\s*gen\b|\bg([1-6])\b"),
      gen_v: c.(~S"^\s*v\b"),
      leading_code: c.(~S"^(\d{2})(x)?\b"),
      mpn_in_title: ci.(~S"\b(?:gl)?[pue][a-z0-9]\d{3}[a-z0-9-]*|\bg\d{2}c?\d{3}us\b|\bg\d{4}[a-z]*aut\b"),
      mpn_gen_us: ci.(~S"^G(\d{2}C?)([345])(\d{2})US$"),
      mpn_aut: ci.(~S"^G(\d{2})\d{2}[A-Z]*AUT$"),
      mpn_letter: ci.(~S"^(?:GL)?([PUE])([A-Z0-9])(\d{2})(\d)"),
      mpn_tb: ci.(~S"\d(?:mos)?tb\b"),
      key_strip: c.("[^a-z0-9]+"),
      words: c.("[a-z0-9.&+]+")
    }
  end

  # Python: re.compile("|".join(patterns), re.I), or nil for no patterns
  defp any_rx([]), do: nil
  defp any_rx(patterns), do: Py.compile(Enum.join(patterns, "|"), true)

  defp compile_dict(d) do
    ci = &Py.compile(&1, true)
    bw = Py.escape(d.brand_word)

    brand_any =
      if d.brand_rx == "",
        do: ci.("(?<![a-z])" <> bw <> "(?![a-z])"),
        else: ci.(d.brand_rx)

    numeric =
      if not d.terms? do
        %{
          find:
            ci.(
              "(?<![a-z0-9.])(?:" <>
                bw <>
                ~S"\s*-?\s*g?\s*-?\s*|g)(\d{2})(?:(sf|x|c|l|m|s)|\s(sf|x)(?![a-z0-9]))?(?:g([1-6])(?:us)?|(v))?(fs|mos|rtf)?" <>
                ~S'(?![a-z0-9&"+/])(?!\s*-?\s*(?:round|rounds|rd|rds|rnd|mag|mags|magazine)\b)'
            ),
          own: ci.(~S"^\W*" <> bw <> ~S"\b"),
          bare:
            if(d.bare_model_tokens != [],
              do: Py.compile(~S"\b(" <> Enum.join(d.bare_model_tokens, "|") <> ~S")\b")
            )
        }
      end

    Map.merge(d, %{
      rewrite: Enum.map(d.title_rewrite, fn {k, v} -> {ci.(k), Py.template(v)} end),
      exclude_rx: any_rx(d.exclude),
      exclude_soft_rx: any_rx(d.exclude_soft),
      block_rx: any_rx(d.other_brand_block),
      brand_any: brand_any,
      brand_start: if(d.brand_rx != "", do: ci.(~S"^\W*(?:" <> d.brand_rx <> ")")),
      config_rx: Enum.map(d.configs, fn {name, p} -> {name, ci.(p)} end),
      # (?<![a-z0-9])NAME(?![a-z0-9]): the config is already spelled out in a model name
      config_in_name:
        Map.new(d.configs, fn {name, _} -> {name, ci.("(?<![a-z0-9])" <> Py.escape(name) <> "(?![a-z0-9])")} end),
      feature_rx: Enum.map(d.features, fn {name, p} -> {name, ci.(p)} end),
      gen_rx: Enum.map(d.gens, fn {label, p} -> {label, ci.(p)} end),
      brand_keys: MapSet.new(d.brand_names, &key/1),
      deny_keys: MapSet.new(d.deny_brand_names, &key/1),
      term_rx:
        Enum.map(d.terms, fn m ->
          Map.merge(m, %{rx: ci.(m.match), not_rx: if(m.not != "", do: ci.(m.not))})
        end),
      numeric: numeric
    })
  end

  @doc false
  # every compiled rule, for the tests
  def all_rules do
    st = state()

    shared = Map.values(st.shared)

    per_dict =
      Enum.flat_map(st.dicts, fn d ->
        Enum.map(d.rewrite, &elem(&1, 0)) ++
          Enum.reject([d.exclude_rx, d.exclude_soft_rx, d.block_rx, d.brand_any, d.brand_start], &is_nil/1) ++
          Enum.map(d.config_rx ++ d.feature_rx ++ d.gen_rx, &elem(&1, 1)) ++
          Map.values(d.config_in_name) ++
          Enum.flat_map(d.term_rx, &Enum.reject([&1.rx, &1.not_rx], fn x -> is_nil(x) end)) ++
          if(d.numeric, do: Enum.reject([d.numeric.find, d.numeric.own, d.numeric.bare], &is_nil/1), else: [])
      end)

    shared ++ per_dict
  end

  # ---------- helpers ----------

  defp accessory?(title, sh) do
    t = title |> Py.html_unescape() |> Py.html_unescape() |> Py.lower()

    if Py.found?(sh.gun_words, t) do
      false
    else
      Enum.any?(Py.finditer(sh.acc_noun, t), fn m ->
        start = Py.m_start(m)
        from = Py.back_cps(t, start, 16)
        not Py.found?(sh.acc_included, binary_part(t, from, start - from))
      end)
    end
  end

  defp translate_dashes(s) do
    for <<c::utf8 <- s>>, into: "" do
      case c do
        c when c in [?‐, ?‑, ?–, ?—] -> "-"
        c when c in [?“, ?”] -> "\""
        ?’ -> "'"
        ?| -> " | "
        ?* -> " "
        c when c in [?®, ?™] -> ""
        c -> <<c::utf8>>
      end
    end
  end

  # lookup key of a brand name: lower case letters and digits only
  defp key(nil), do: ""

  defp key(s) do
    Py.sub(state_shared_key(), s |> Py.html_unescape() |> Py.lower(), [])
  end

  # key/1 runs while the state is being built, so it compiles its own rule
  defp state_shared_key do
    case :persistent_term.get({__MODULE__, :key_rx}, nil) do
      nil ->
        rx = Py.compile("[^a-z0-9]+")
        :persistent_term.put({__MODULE__, :key_rx}, rx)
        rx

      rx ->
        rx
    end
  end

  # Python's _norm(title, d): the part before the dictionary's rewrite rules is the same for every dictionary, so it is
  # computed once per title (`base/1`)
  defp base(s) do
    s = s |> Py.html_unescape() |> translate_dashes()
    s |> Py.lower() |> Py.collapse_ws() |> Py.strip()
  end

  defp norm(base, d), do: Enum.reduce(d.rewrite, base, fn {rx, to}, s -> Py.sub(rx, s, to) end)

  def list_brands, do: Enum.map(Data.dicts(), & &1.brand)

  # ---------- numeric mode (Glock): codes like 19, 19X, 43X, 20SF; generation from the title or the part number ----------

  defp find_models(t, d) do
    Enum.flat_map(Py.finditer(d.numeric.find, t), fn m ->
      num = m |> Py.group(t, 1) |> String.downcase()
      g2 = Py.group_str(m, t, 2)
      suf = String.upcase(if g2 != "", do: g2, else: Py.group_str(m, t, 3))

      code =
        cond do
          Map.has_key?(d.codes, num <> suf) -> num <> suf
          Map.has_key?(d.codes, num) -> num
          true -> nil
        end

      if code do
        gen =
          cond do
            Py.group_str(m, t, 4) != "" -> Py.group(m, t, 4)
            Py.group_str(m, t, 5) != "" -> "V"
            true -> ""
          end

        [%{code: code, num: num, end: Py.m_end(m), mos: Py.lower(Py.group_str(m, t, 6)) == "mos", gen: gen}]
      else
        []
      end
    end)
  end

  defp decode_mpn(name, mpn, sku, d, sh) do
    in_title = name |> then(&Py.finditer(sh.mpn_in_title, &1)) |> Enum.map(&Py.group(&1, name))

    Enum.find_value([mpn || "", sku || ""] ++ in_title, &decode_one(Py.strip(&1), d, sh))
  end

  defp decode_one(c, d, sh) do
    gen_us = Py.match_at(sh.mpn_gen_us, c)
    aut = Py.match_at(sh.mpn_aut, c)

    cond do
      gen_us != nil and Map.has_key?(d.codes, String.upcase(Py.group(gen_us, c, 1))) ->
        %{code: String.upcase(Py.group(gen_us, c, 1)), mpn: c, gen: Py.group(gen_us, c, 2)}

      aut != nil and Map.has_key?(d.codes, Py.group(aut, c, 1)) ->
        %{code: Py.group(aut, c, 1), mpn: c, gen: ""}

      m = Py.match_at(sh.mpn_letter, c) ->
        letter = String.upcase(Py.group(m, c, 2))
        num = Py.group(m, c, 3)
        num = Map.get(d.mpn_model_alias, num, num)
        code = Map.get(d.mpn_letter_model, letter <> num, num)
        if Map.has_key?(d.codes, code), do: %{code: code, mpn: c, gen: Map.get(d.mpn_letter_gen, letter, "")}

      true ->
        nil
    end
  end

  defp parse_numeric(t, name, opts, d, sh) do
    n = d.numeric
    pm = decode_mpn(name, opts[:mpn], opts[:sku], d, sh)

    if pm == nil and d.exclude_soft_rx != nil and Py.found?(d.exclude_soft_rx, t) do
      nil
    else
      own =
        if opts[:brand],
          do: MapSet.member?(d.brand_keys, opts[:brand_key]) or pm != nil,
          else: pm != nil or Py.match_at(n.own, t) != nil

      models = find_models(t, d)

      models =
        with [] <- models,
             true <- own,
             m when m != nil <- Py.match_at(sh.leading_code, t),
             code = Py.group(m, t, 1) <> String.upcase(Py.group_str(m, t, 2)),
             true <- Map.has_key?(d.codes, code) do
          [%{code: code, num: Py.group(m, t, 1), end: Py.m_end(m), mos: false, gen: ""}]
        else
          _ -> models
        end

      models =
        with [] <- models,
             true <- own,
             bare when bare != nil <- n.bare,
             m when m != nil <- Py.search(bare, t) do
          tok = Py.group(m, t, 1)
          [%{code: String.upcase(tok), num: Py.take_cps(tok, 2), end: Py.m_end(m), mos: false, gen: ""}]
        else
          _ -> models
        end

      blocked = not own and (models == [] or (d.block_rx != nil and Py.found?(d.block_rx, t)))
      unless blocked, do: numeric_hit(t, d, sh, pm, own, models)
    end
  end

  defp numeric_hit(t, d, sh, pm, own, models) do
    first = List.first(models)

    {code, src} =
      cond do
        first ->
          longest =
            Enum.reduce(models, first.code, fn x, code ->
              if x.num == first.num and Py.cp_count(x.code) > Py.cp_count(code), do: x.code, else: code
            end)

          {longest, :title}

        own and pm != nil ->
          {pm.code, :mpn}

        true ->
          {nil, nil}
      end

    if code do
      gen =
        cond do
          first && first.gen != "" ->
            first.gen

          m = Py.search(sh.gen, t) ->
            Enum.find([Py.group(m, t, 1), Py.group(m, t, 2), Py.group(m, t, 3)], "", &(&1 not in [nil, ""]))

          first && Py.match_at(sh.gen_v, binary_part(t, first.end, byte_size(t) - first.end)) ->
            "V"

          pm && pm.gen != "" && pm.code == code ->
            pm.gen

          true ->
            ""
        end

      gen = if code in d.no_gen_models and gen != "V", do: "", else: gen
      mos = (first && first.mos) || (pm != nil and String.contains?(Py.lower(pm.mpn), "mos"))

      configs =
        for {name, rx} <- d.config_rx, Py.found?(rx, t) or (name == "MOS" and mos), do: name

      features = for {name, rx} <- d.feature_rx, Py.found?(rx, t), do: name

      features =
        if pm != nil and Py.found?(sh.mpn_tb, pm.mpn) and "Threaded Barrel" not in features,
          do: features ++ ["Threaded Barrel"],
          else: features

      %{code: code, family: Map.fetch!(d.codes, code), gen: gen, configs: configs, features: features, src: src}
    end
  end

  # ---------- terms mode (all other brands): ordered list of model patterns, first match wins ----------

  defp parse_terms(t, brand, bkey, d) do
    cond do
      brand && MapSet.member?(d.deny_keys, bkey) ->
        nil

      true ->
        own =
          (brand != nil and MapSet.member?(d.brand_keys, bkey)) or
            (d.brand_start != nil and Py.found?(d.brand_start, t))

        if not own and (not Py.found?(d.brand_any, t) or (d.block_rx != nil and Py.found?(d.block_rx, t))) do
          nil
        else
          hit = Enum.find(d.term_rx, &(Py.found?(&1.rx, t) and not (&1.not_rx != nil and Py.found?(&1.not_rx, t))))
          terms_hit(t, d, hit, own)
        end
    end
  end

  defp terms_hit(_t, _d, nil, _own), do: nil

  defp terms_hit(t, d, hit, own) do
    if not own and d.other_brand_models != [] and hit.name not in d.other_brand_models do
      nil
    else
      gen = Enum.find_value(d.gen_rx, "", fn {label, rx} -> if Py.found?(rx, t), do: label end)

      configs =
        d.config_rx
        |> Enum.filter(fn {name, rx} ->
          imp = d.implied |> Map.get(name, %{}) |> Map.get(hit.family, [])
          name in hit.configs and (Py.found?(rx, t) or (gen != "" and gen in imp) or name in hit.implied_configs)
        end)
        |> Enum.map(&elem(&1, 0))

      features = for {name, rx} <- d.feature_rx, Py.found?(rx, t), do: name
      %{code: hit.name, family: hit.family, gen: gen, configs: configs, features: features, src: :title}
    end
  end

  # which matching dictionary wins: the product's own brand -> brand at the start of the title -> brand mentioned
  # earlier (positions in code points, like Python)
  defp rank(base, d, opts) do
    if opts[:brand] && MapSet.member?(d.brand_keys, opts[:brand_key]) do
      {0, 0}
    else
      t = norm(base, d)

      case Py.search(d.brand_any, t) do
        nil ->
          {2, 1_000_000}

        m ->
          pos = Py.cp_index(t, Py.m_start(m))
          if pos <= 2, do: {1, 0}, else: {2, pos}
      end
    end
  end

  defp words(s) do
    rx = state().shared.words
    s = Py.lower(s)
    s |> then(&Py.finditer(rx, &1)) |> MapSet.new(&Py.group(&1, s))
  end

  defp leaf(r, d) do
    s =
      cond do
        d.terms? -> if r.gen != "", do: r.code <> " " <> r.gen, else: r.code
        r.gen == "V" -> d.brand <> " " <> r.code <> " V"
        r.gen != "" -> d.brand <> " " <> r.code <> " Gen " <> r.gen
        true -> d.brand <> " " <> r.code
      end

    s =
      Enum.reduce(r.configs, s, fn c, s ->
        # skip a config already spelled out in the name ("Plus Shield" on "S&W M&P Shield Plus")
        spelled =
          Map.get_lazy(d.config_in_name, c, fn ->
            Py.compile("(?<![a-z0-9])" <> Py.escape(c) <> "(?![a-z0-9])", true)
          end)

        if not Py.found?(spelled, s) and not MapSet.subset?(words(c), words(s)),
          do: s <> " " <> c,
          else: s
      end)

    needed = Map.get(d.needed, r.family, [])

    Enum.reduce(d.feature_order, s, fn f, s ->
      if f in r.features and f in needed, do: s <> " " <> f, else: s
    end)
  end

  defp parse_one(title, base, d, opts) do
    t = norm(base, d)
    brand = opts[:brand]

    cond do
      d.exclude_rx != nil and Py.found?(d.exclude_rx, t) ->
        nil

      d.terms? ->
        parse_terms(t, brand, opts[:brand_key], d)

      # the numeric dictionary (Glock) only runs when the brand is given or named in the title;
      # otherwise part-number decoding picks up other brands' codes (CVA "PR3110S" -> "Glock 31")
      not ((brand && MapSet.member?(d.brand_keys, opts[:brand_key])) || Py.found?(d.brand_any, t)) ->
        nil

      true ->
        parse_numeric(t, title, opts, d, state().shared)
    end
  end

  def identify_model(title, opts) do
    st = state()
    sh = st.shared

    if title in [nil, ""] or Py.found?(sh.airgun, title) or accessory?(title, sh) do
      nil
    else
      base = base(title)
      opts = Keyword.put(opts, :brand_key, if(opts[:brand], do: key(opts[:brand])))

      hits =
        Enum.flat_map(st.dicts, fn d ->
          case parse_one(title, base, d, opts) do
            nil -> []
            r -> [{rank(base, d, opts), d, r}]
          end
        end)

      case Enum.sort_by(hits, &elem(&1, 0)) do
        [] ->
          nil

        [{_, d, r} | _] ->
          family =
            case Map.get(d.family_display, r.family) do
              f when f not in [nil, ""] -> f
              _ -> if d.terms?, do: r.family, else: d.brand <> " " <> r.family
            end

          %ModelMatch{
            brand: d.brand,
            family: family,
            model: leaf(r, d),
            generation: r.gen,
            configs: r.configs,
            features: r.features,
            source: r.src
          }
      end
    end
  end
end
