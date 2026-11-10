defmodule GunsNPrices.Specs do
  @moduledoc false
  # Numbers from product titles: magazine capacity, barrel length, rounds per box and cost per round.

  alias GunsNPrices.Py

  @num "(\\d{1,3}(?:,\\d{3})+|\\d{1,5})"
  @inch ~S'(?:"|in\b(?!\s*(?:1\b|stock\b|one\b))\.?|inch(?:es)?\b|-inch\b|-in\b)'
  # 18.5 / 16 1/2
  @len ~S"(\d{1,2}(?:\.\d{1,3})?)(?:[\s-]+(\d{1,2})/(\d{1,2}))?"
  @bbl ~S"(?:bbl|brl|barrel)\b"
  @b ~S"(?<![a-z0-9.#$/])"

  @caliber_slash MapSet.new([
                   {"30", "30"},
                   {"45", "70"},
                   {"30", "06"},
                   {"22", "250"},
                   {"25", "06"},
                   {"38", "55"},
                   {"44", "40"},
                   {"32", "20"},
                   {"38", "40"},
                   {"25", "20"},
                   {"32", "40"}
                 ])

  defp rules do
    case :persistent_term.get({__MODULE__, :rules}, nil) do
      nil ->
        r = build_rules()
        :persistent_term.put({__MODULE__, :rules}, r)
        r

      r ->
        r
    end
  end

  defp build_rules do
    c = &Py.compile/1

    %{
      ammo:
        c.(
          ~S"\b(?:ammo|ammunition|shotshells?|shot ?shells?|cartridges?|bullets?|primers?|slugs?|buckshot|pellets?|bbs?|grains?|\d+\s*gr|" <>
            ~S"per box|box of|rounds? box|rds?/box)\b|/\s*(?:box|bx|pk|pack|case|cs|tin)\b"
        ),
      # 15+1
      cap_plus: c.(~S"(?<![\d.:/x])(\d{1,3})\s*\+\s*1(?!\d)"),
      cap_rd:
        c.(
          ~S"(?<![\d.:/x])(\d{1,3})\s*-?\s*(?:rd|rds|rnd|rnds|round|rounds|shot|shots)\b(?!\s*/?\s*(?:per\b|box|bx|pack|pk|case))"
        ),
      # "13rd/15rd", "1-30Rd/1-10Rd Mag": ships with magazines of two sizes - take the larger one
      cap_pair:
        c.(
          ~S"(?<![\d.:/x])(\d{1,3})\s*-?\s*(?:rd|rds|rnd|rnds|rounds?)?\s*/\s*(?:1?-)?(\d{1,3})\s*-?\s*(?:rd|rds|rnd|rnds|rounds?)\b"
        ),
      cap_mag: c.(~S'\b(?:cap|capacity)\s*[:=]?\s*(\d{1,3})\b(?!\s*(?:"|in\b|gr\b))'),
      bar_tagged: [
        # 20" barrel, 22 bbl
        c.(~S"(?<![\d.:/x#$-])" <> @len <> ~S"\s*-?\s*" <> @inch <> ~S"?\s*" <> @bbl),
        # barrel: 20"
        c.(~S"\b(?:bbl|brl|barrel)\s*(?:length)?\s*[:=]?\s*" <> @len <> ~S"\s*" <> @inch)
      ],
      bar_inch: c.(~S"(?<![\d.:/x#$-])" <> @len <> ~S"\s*-?\s*" <> @inch),
      not_barrel_after:
        c.(
          ~S"\s*-?\s*(?:chamber|chbr|chmbr|shells?|m-?lok|mlok|handguard|hg\b|rail|keymod|quad|lop\b|length of pull|oal\b|twist|rate)"
        ),
      not_barrel_before:
        c.(
          ~S"(?:lop|oal|overall|length of pull|pull|twist|1:|chamber|m-?lok|mlok|handguard|rail|sight radius)\s*[:=]?\s*$"
        ),
      shotgun:
        c.(
          ~S"\b(?:\d{1,2}|410)\s*(?:ga|gauge|g)\b|\.410|shotgun|o/u|over/under|sxs|side by side|\b(?:12|16|20|28|410)/\d\d\b"
        ),
      # "O/U 12/28": gauge / barrel length (10 is left out: "10/22" is a Ruger rifle)
      gauge_slash:
        c.(~S"(?<![a-z0-9./$#-])(?:12|16|20|28|410)/(1[89](?:\.5)?|2\d|3[0-4])(?![\d/.])(?!\s*(?:ga|gauge|rd|round))"),
      rpb: [
        c.(
          @b <>
            @num <>
            ~S"\s*-?\s*(?:rd|rds|round|rounds|rnd|rnds|ct|count|pcs|pc|cartridges|shells|shotshells|bullets)\b(?!\s*(?:mag|magazine|capacity|cap)\b)"
        ),
        c.(@b <> @num <> ~S"\s*(?:/\s*|per\s+)(?:box|bx|pack|pk|case|cs|tin|can|bag|ct)\b"),
        c.(~S"(?:box|pack|case|tin|bx|bag|can) of\s*" <> @num),
        c.(@b <> @num <> ~S"\s*-?\s*(?:pack|pk|packs)\b")
      ],
      # distributor notation "50/10", "20/25": rounds per box / boxes per case
      box_case: c.(~S'(?<![\d.\-/])(5|10|15|18|20|25|30|40|50|100|200|250|500|1000)\s*/\s*(\d{1,3})(?![\d/."])')
    }
  end

  defp prep(text) do
    (text || "")
    |> Py.html_unescape()
    |> Py.html_unescape()
    |> Py.lower()
    |> String.replace(["”", "″", "“"], "\"")
    |> String.replace("''", "\"")
    |> String.replace("’’", "\"")
    |> String.replace(["®", "™"], "")
    |> Py.collapse_ws()
  end

  def looks_like_ammo?(title), do: Py.found?(rules().ammo, prep(title))

  def magazine_capacity(title) do
    r = rules()
    s = prep(title)

    pair =
      case Py.search(r.cap_pair, s) do
        nil -> nil
        m -> max(Py.int(Py.group(m, s, 1)), Py.int(Py.group(m, s, 2)))
      end

    if pair != nil and pair >= 1 and pair <= 110 do
      pair
    else
      Enum.find_value([r.cap_plus, r.cap_rd, r.cap_mag], fn rx ->
        Enum.find_value(Py.finditer(rx, s), fn m ->
          n = Py.int(Py.group(m, s, 1))
          if n >= 1 and n <= 110, do: n
        end)
      end)
    end
  end

  defp length_of(m, s) do
    v = Py.float(Py.group(m, s, 1))
    num = Py.group(m, s, 2)
    den = Py.group(m, s, 3)

    if num not in [nil, ""] and den not in [nil, ""] and Py.int(den) in [2, 4, 8, 16] and Py.int(num) < Py.int(den),
      do: v + Py.int(num) / Py.int(den),
      else: v
  end

  def barrel_length(title) do
    r = rules()
    s = prep(title)

    tagged =
      Enum.find_value(r.bar_tagged, fn rx ->
        Enum.find_value(Py.finditer(rx, s), fn m ->
          v = length_of(m, s)
          if v >= 1.5 and v <= 36, do: v
        end)
      end)

    cond do
      tagged != nil ->
        tagged

      m = Py.search(r.gauge_slash, s) ->
        Py.float(Py.group(m, s, 1))

      true ->
        shotgun = Py.found?(r.shotgun, s)

        Enum.find_value(Py.finditer(r.bar_inch, s), fn m ->
          v = length_of(m, s)
          start = Py.m_start(m)
          before = binary_part(s, Py.back_cps(s, start, 20), start - Py.back_cps(s, start, 20))

          cond do
            v < 1.5 or v > 36 -> nil
            Py.match_at(r.not_barrel_after, s, Py.m_end(m)) != nil -> nil
            Py.found?(r.not_barrel_before, before) -> nil
            # 3" chamber
            shotgun and v <= 3.5 -> nil
            true -> v
          end
        end)
    end
  end

  def rounds_per_box(title) do
    r = rules()
    s = prep(title)

    # the first pattern that matches decides (its first match only, like Python's search)
    from_rpb =
      Enum.reduce_while(r.rpb, nil, fn rx, _ ->
        case Py.search(rx, s) do
          nil ->
            {:cont, nil}

          m ->
            n = m |> Py.group(s, 1) |> String.replace(",", "") |> Py.int()
            if n >= 1 and n <= 20_000, do: {:halt, n}, else: {:cont, nil}
        end
      end)

    from_rpb ||
      Enum.find_value(Py.finditer(r.box_case, s), fn m ->
        a = Py.group(m, s, 1)
        b = Py.group(m, s, 2)
        if not MapSet.member?(@caliber_slash, {a, b}) and b not in ["2", "4", "8", "16", "32"], do: Py.int(a)
      end)
  end

  def cost_per_round(price, rounds) do
    if is_number(price) and is_integer(rounds) and price > 0 and rounds > 0,
      do: Py.round4(price / rounds),
      else: nil
  end
end
