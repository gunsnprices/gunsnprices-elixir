defmodule GunsNPrices.Calibers do
  @moduledoc false
  # Recognize calibers in product titles and normalize caliber fields. The caliber list and the retailer spellings come
  # from the GunsNPrices calibers dataset; on top of them common title forms are generated: "300 Blackout", "12ga",
  # "7.62 x 39", "45 Auto", "6.5 Creed", ".308 Winchester" and so on.

  alias GunsNPrices.{Caliber, Data, Py}

  # word -> spellings used in titles
  @syn %{
    "win" => ["win", "winchester"],
    "winchester" => ["winchester", "win"],
    "rem" => ["rem", "remington"],
    "remington" => ["remington", "rem"],
    "mag" => ["mag", "magnum"],
    "magnum" => ["magnum", "mag"],
    "wby" => ["wby", "weatherby"],
    "weatherby" => ["weatherby", "wby"],
    "spl" => ["spl", "special"],
    "special" => ["special", "spl"],
    "sprg" => ["sprg", "springfield", "spfd"],
    "springfield" => ["springfield", "sprg", "spfd"],
    "government" => ["government", "govt", "gov"],
    "acp" => ["acp", "auto"],
    "auto" => ["auto", "acp"],
    "s&w" => ["s&w", "s & w", "sw", "smith & wesson", "smith and wesson", "smith&wesson"],
    "blackout" => ["blackout", "blk", "black out"],
    "creedmoor" => ["creedmoor", "creed", "cm", "crd", "creedmore"],
    "parabellum" => ["parabellum", "para", "luger"],
    "gauge" => ["gauge", "ga", "gauges"],
    "bore" => ["bore", "ga", "gauge"],
    "lr" => ["lr", "long rifle"],
    "h&h" => ["h&h", "h & h", "holland & holland", "holland and holland"],
    "h&r" => ["h&r", "h & r"],
    "bm" => ["bm", "bushmaster", "bush"]
  }
  # a word that may be left out ("300 Blackout" for ".300 AAC Blackout")
  @optional ~w(aac nato win winchester rem remington sprg springfield government)
  @sep "[\\s\\-]*"

  # common title spellings that the synonym table does not produce
  @extra %{
    ".300 AAC Blackout" => ["300 aac", "300 bo", "300 black out", "300 blackout", "300 blk"],
    "6.5mm Creedmoor" => ["6.5 creedmoor", "6.5 crd", "6.5 cm", "6.5mm cm", "6.5 cr"],
    "6mm Creedmoor" => ["6 creedmoor"],
    ".22 LR" => ["22lr", "22 lr", "22 long rifle"],
    ".22 WMR" => ["22 mag", "22 magnum", "22 win mag", "22 wmr"],
    "5.56×45mm NATO" => ["5.56 nato", "5.56mm nato", "556 nato", "5.56x45", "5.56", "5.56mm", "5.56 mm"],
    "7.62x51mm NATO" => ["7.62 nato", "7.62mm nato", "762 nato", "762x51"],
    "7.62x39mm" => ["762x39"],
    ".410 Bore" => ["410 ga", "410 gauge", "410 bore"],
    ".45 Colt" => ["45 lc", "45 long colt"],
    ".44 S&W Special" => ["44 spl", "44 special", "44 spcl"],
    ".38 S&W Special" => ["38 spl", "38 special", "38 spcl", "38 spc", "38 sp", "38 spp", "38+p"],
    ".357 Mag" => ["357 rm", "357 rem mag", "357 rem magnum", "357 remington magnum", "357 remington mag"],
    "9×19mm Parabellum" => ["9mm luger", "9mm para", "9 mm luger", "9mm"],
    "10mm Auto" => ["10mm", "10 mm"],
    ".45 ACP" => ["45 acp", "45 auto", "45 automatic", "45 automatic colt pistol"],
    ".40 S&W" => ["40 s&w", "40 sw", "40 cal", "40s", ".40"],
    ".380 ACP" => ["380 acp", "380 auto", "380"],
    ".243 Win" => ["243", ".243"],
    ".308 Win" => ["308", ".308"],
    ".350 Legend" => [".350", "350 leg", "350 lgnd", "350 lgd"],
    ".450 BM" => ["450 bushmaster", "450 bush"],
    ".204 Ruger" => [".204"],
    ".177" => ["177", ".177"],
    ".300 Win Mag" => ["300 wm"],
    "7mm Remington Magnum" => ["7mm rm", "7 rm", "7mm rem mag"],
    ".338 Lapua Mag" => ["338 lapua", "338 lap"],
    ".30 Carbine" => ["30 m1", "30 m1 carbine"],
    ".30-06 Springfield" => ["30-06 sp"],
    "7.92×57mm Mauser" => ["8x57", "8x57mm", "8x57 js", "8x57 is"],
    ".50 AE" => ["50 action express"],
    "12 Gauge" => ["12 ga", "12ga", "12 gauge", "12-gauge", "12g"],
    "20 Gauge" => ["20 ga", "20ga", "20 gauge", "20-gauge", "20g"],
    "16 Gauge" => ["16 ga", "16ga", "16 gauge", "16g"],
    "28 Gauge" => ["28 ga", "28ga", "28 gauge", "28g"],
    "10 Gauge" => ["10g"]
  }

  # A bare number or "Nmm" in a title is usually something else, not a caliber; these exceptions were checked against
  # GunsNPrices listings (right in 97%+ of cases).
  @allow_bare ~w(380 410 9mm 10mm) ++
                ["10 mm", "5.56", "5.56mm", "5.56 mm", "243", ".243", "308", ".308", ".40", ".350", ".204"] ++
                ["177", ".177"]

  # Shotguns "O/U 12/28": gauge / barrel length; on ammo "20/25" is rounds per box / boxes per case;
  # "20/28 gauge" is a two-gauge set. ".357/.38 Spl" names both cartridges.
  @context [
    {"(?<![a-z0-9./$#-])12/(?:1[89]|2\\d|3[0-4])(?:\\.5)?(?![\\d/.])(?!\\s*(?:ga|gauge|rd|round))", "12gauge"},
    {"(?<![a-z0-9./$#-])20/(?:18|18\\.5|2[0-46-9]|3[0-2])(?![\\d/.])(?!\\s*(?:ga|gauge|rd|round))", "20gauge"},
    {"(?<![a-z0-9./$#-])28/(?:2[6-9]|3[0-2])(?![\\d/.])(?!\\s*(?:ga|gauge|rd|round))", "28gauge"},
    {"(?<![a-z0-9.$#-])\\.?357(?=\\s*/\\s*\\.?38)", "357mag"}
  ]

  defp rules do
    case :persistent_term.get({__MODULE__, :rules}, nil) do
      nil ->
        r = %{
          key_dot: Py.compile("(?<=\\d)\\.(?=\\d)"),
          key_strip: Py.compile("[^a-z0-9#&]+"),
          lead_dot: Py.compile("^\\."),
          ws: Py.compile("\\s+"),
          mm_pair: Py.compile("\\A(?:\\.?\\d+(?:\\.\\d+)?x\\d+mm[a-z]*)\\Z"),
          mm_single: Py.compile("\\A(?:\\d+mm)\\Z"),
          x_digits: Py.compile("(?<=\\d)x(?=\\d)"),
          bare: Py.compile("^\\.?\\d+(?:\\.\\d+)?(?:\\s*mm)?$"),
          gram: Py.compile("^\\d+\\s?g$"),
          has_digit: Py.compile("\\d")
        }

        :persistent_term.put({__MODULE__, :rules}, r)
        r

      r ->
        r
    end
  end

  # lookup key of a spelling: lower case, letters and digits only, "&" as "and", decimal points kept
  defp key(s) do
    r = rules()
    s = (s || "") |> Py.html_unescape() |> Py.lower() |> String.replace(["×", "х"], "x")
    s = Py.sub(r.key_dot, s, ["#"])
    s = Py.sub(r.key_strip, s, [])
    s |> String.replace("#", ".") |> String.replace("&", "and")
  end

  defp tokens(name) do
    r = rules()
    s = name |> Py.html_unescape() |> Py.lower() |> String.replace("×", "x")
    s = Py.sub(r.lead_dot, s, [])
    s |> Py.strip() |> split_ws(r) |> Enum.reject(&(&1 == ""))
  end

  # Python `re.split(r"\s+", s)`
  defp split_ws(s, r) do
    {parts, last} =
      Enum.reduce(Py.finditer(r.ws, s), {[], 0}, fn m, {acc, last} ->
        {[binary_part(s, last, Py.m_start(m) - last) | acc], Py.m_end(m)}
      end)

    Enum.reverse([binary_part(s, last, byte_size(s) - last) | parts])
  end

  defp token_alts(tok) do
    r = rules()

    cond do
      # 9x19mm, 5.56x45mm, 7.62x54mmr
      Py.match_at(r.mm_pair, tok) ->
        [tok, String.replace(tok, "mm", "")]

      Py.match_at(r.mm_single, tok) ->
        [tok, binary_part(tok, 0, byte_size(tok) - 2) <> " mm"]

      true ->
        alts = Map.get(@syn, tok, [tok])
        if tok in @optional, do: alts ++ [""], else: alts
    end
  end

  defp bare?(v), do: Py.match_at(rules().bare, v) != nil and v not in @allow_bare

  # itertools.product order (the last position changes fastest), lazily
  defp product([]), do: [[]]
  defp product([alts | rest]), do: Stream.flat_map(alts, fn x -> Stream.map(product(rest), &[x | &1]) end)

  # all title spellings generated from a name (at most 400 combinations, like the reference implementation)
  defp variants(name) do
    toks = tokens(name)

    if toks == [] or String.contains?(name, "/") do
      []
    else
      toks
      |> Enum.map(&token_alts/1)
      |> product()
      |> Enum.take(400)
      |> Enum.map(fn combo -> combo |> Enum.reject(&(&1 == "")) |> Enum.join(" ") end)
      |> Enum.filter(&(&1 != "" and not bare?(&1)))
      |> Enum.uniq()
      |> Enum.sort()
    end
  end

  # Python-syntax pattern for one spelling: optional leading dot, flexible "x" and separators
  defp spelling_rx(variant) do
    r = rules()

    body =
      variant
      |> String.split(" ")
      |> Enum.map(fn tok ->
        t = Py.escape(tok)
        t = Py.sub(r.x_digits, t, ["\\s*x\\s*"])
        String.replace(t, "\\-", @sep)
      end)
      |> Enum.join(@sep)

    case String.to_charlist(variant) do
      [c | _] -> if Py.digit_value(c), do: "\\.?" <> body, else: body
      [] -> body
    end
  end

  defp index do
    case :persistent_term.get({__MODULE__, :index}, nil) do
      nil ->
        ix = build_index()
        :persistent_term.put({__MODULE__, :index}, ix)
        ix

      ix ->
        ix
    end
  end

  defp build_index do
    r = rules()
    rows = Data.calibers()
    cals = Enum.map(rows, &%Caliber{id: &1.id, name: &1.name, type: &1.type, url: &1.url})
    by_id = Map.new(cals, &{&1.id, &1})

    # key -> [{n, caliber}] in insertion order; `order` keeps the keys in the order they were first seen
    {order, conflict, pats} =
      rows
      |> Enum.zip(cals)
      |> Enum.reduce({[], %{}, %{}}, fn {c, cal}, acc ->
        names = [c.name, c.site_name | c.aliases] ++ Map.get(@extra, c.name, [])

        Enum.reduce(names, acc, fn n, acc ->
          own = n |> Py.html_unescape() |> Py.lower()
          vs = variants(n) ++ if(bare?(own), do: [], else: [own])

          Enum.reduce(vs, acc, fn v, {order, conflict, pats} = acc ->
            k = key(v)

            if k == "" or not Py.found?(r.has_digit, k) do
              acc
            else
              {order, cands} =
                case conflict do
                  %{^k => cands} -> {order, cands}
                  _ -> {[k | order], []}
                end

              cands = if Enum.all?(cands, fn {_, x} -> x.id != cal.id end), do: cands ++ [{c.n, cal}], else: cands

              pat =
                if v != own or not String.contains?(v, "/"), do: spelling_rx(v), else: Py.escape(v)

              {order, Map.put(conflict, k, cands), Map.put_new(pats, k, pat)}
            end
          end)
        end)
      end)

    # one spelling, several calibers: keep the one with 10x+ more listings, otherwise the spelling is ambiguous
    by_key =
      order
      |> Enum.reverse()
      |> Enum.flat_map(fn k ->
        case Enum.sort_by(conflict[k], fn {n, _} -> -n end) do
          [{_, cal}] -> [{k, cal}]
          [{n0, cal}, {n1, _} | _] when n0 >= 10 * max(1, n1) -> [{k, cal}]
          _ -> []
        end
      end)

    # longer patterns first (stable, like Python's sorted)
    keys = by_key |> Enum.map(&elem(&1, 0)) |> Enum.sort_by(&(-Py.cp_count(pats[&1])))
    # (?<![a-z0-9.$])(?:SPELLINGS)(?![a-z0-9]), in as many parts as PCRE2's size limit needs
    big = Py.compile_alternation("(?<![a-z0-9.$])(?:", Enum.map(keys, &pats[&1]), ")(?![a-z0-9])", true)

    %{
      calibers: cals,
      by_id: by_id,
      by_key: Map.new(by_key),
      keys: keys,
      big: big,
      context: Enum.map(@context, fn {p, id} -> {Py.compile(p), Map.fetch!(by_id, id)} end)
    }
  end

  defp prep(text) do
    (text || "")
    |> Py.html_unescape()
    |> Py.lower()
    |> String.replace("×", "x")
    |> String.replace(["”", "″"], "\"")
    |> String.replace(["®", "™"], "")
    |> Py.collapse_ws()
  end

  def find_calibers(text) do
    ix = index()
    r = rules()
    s = prep(text)
    co2 = String.contains?(s, "co2")

    big =
      Enum.flat_map(Py.finditer_multi(ix.big, s), fn m ->
        spelling = Py.group(m, s)

        # "12g" next to CO2 is a 12-gram CO2 cartridge, not 12 gauge
        with false <- co2 and Py.match_at(r.gram, spelling) != nil,
             %Caliber{} = cal <- Map.get(ix.by_key, key(spelling)) do
          [{Py.m_start(m), cal}]
        else
          _ -> []
        end
      end)

    context = for {rx, cal} <- ix.context, m <- Py.finditer(rx, s), do: {Py.m_start(m), cal}

    (big ++ context)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
    |> Enum.uniq_by(& &1.id)
  end

  def find_caliber(text), do: text |> find_calibers() |> List.first()

  def normalize_caliber(value) do
    Map.get(index().by_key, key(value)) || find_caliber(value)
  end

  def list_calibers, do: Enum.sort_by(index().calibers, & &1.name)

  def caliber_by_id(id), do: Map.get(index().by_id, id)

  @doc false
  # the spelling table, for the tests: [{key, caliber id}] in the order the big pattern tries them
  def spellings do
    ix = index()
    Enum.map(ix.keys, &{&1, ix.by_key[&1].id})
  end
end
