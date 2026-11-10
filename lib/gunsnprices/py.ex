defmodule GunsNPrices.Py do
  @moduledoc false
  # Python compatibility: the parsing rules (the patterns in this package and the ~3,000 patterns in the model
  # dictionaries) are written for Python's `re` module, the engine of the reference implementation, and the code around
  # them relies on Python's string semantics. This module reproduces both on top of Erlang's `:re` (PCRE2):
  #
  # * the pattern syntax is translated where PCRE2 reads it differently: `\w` is `[\p{L}\p{N}_]` (PCRE2's Unicode `\w`
  #   also takes combining marks), `\s` and `\d` are spelled out from Python's own tables (`\s` covers U+001C..U+001F),
  #   `\Z` is `\z`, `{` that is not a repetition is a literal, `[` inside a class is a literal, and with `re.I` the
  #   letter i also matches "ı" and "İ" like in Python;
  # * `\b` runs natively unless the text has a combining mark or a connector punctuation (where PCRE2's word
  #   characters differ from Python's); then a look-around version with Python's word characters is used;
  # * positions are counted in code points where Python counts them, `lower()` handles the final sigma, numbers are
  #   read from any script's digits, and `round()` rounds half to even on the exact binary value.
  #
  # Both engines backtrack with leftmost-first alternation, so the match found is the one Python finds.

  import Bitwise
  alias GunsNPrices.UnicodeTables

  @word "\\p{L}\\p{N}_"
  @word_exact_b "(?:(?<=[\\p{L}\\p{N}_])(?![\\p{L}\\p{N}_])|(?<![\\p{L}\\p{N}_])(?=[\\p{L}\\p{N}_]))"
  @word_exact_nb "(?:(?<=[\\p{L}\\p{N}_])(?=[\\p{L}\\p{N}_])|(?<![\\p{L}\\p{N}_])(?![\\p{L}\\p{N}_]))"
  @i_class "iI\\x{130}\\x{131}"

  # ---------- compiled patterns ----------

  @typedoc false
  @type rx :: %{fast: tuple(), exact: binary() | nil, opts: list()}

  @doc false
  # Translate and compile a Python pattern; `ignore_case` is Python's `re.I`. Raises on a pattern it cannot translate
  # (only patterns that are not in this package; the test suite compiles every rule).
  @spec compile(binary(), boolean()) :: rx()
  def compile(py_pattern, ignore_case \\ false) do
    case try_compile(py_pattern, ignore_case) do
      {:ok, rx} -> rx
      {:error, e} -> raise ArgumentError, "bad pattern #{inspect(py_pattern)}: #{inspect(e)}"
    end
  end

  defp try_compile(py_pattern, ignore_case) do
    {fast, exact} = translate(py_pattern, ignore_case)
    opts = [:unicode, :ucp, {:newline, :lf}] ++ if(ignore_case, do: [:caseless], else: [])

    case :re.compile(fast, opts) do
      {:ok, mp} -> {:ok, %{fast: mp, exact: exact, opts: opts}}
      {:error, e} -> {:error, e}
    end
  end

  @doc false
  # Python `re.compile(prefix + "|".join(alternatives) + suffix)` for an alternation too big for one PCRE2 pattern
  # (64K of compiled code): split into as few patterns as fit. `finditer_multi/2` merges their matches the way the
  # single pattern matches (leftmost start first; at the same start the earlier alternative, i.e. the earlier part).
  def compile_alternation(prefix, alternatives, suffix, ignore_case) do
    case try_compile(prefix <> Enum.join(alternatives, "|") <> suffix, ignore_case) do
      {:ok, rx} ->
        [rx]

      {:error, {~c"regular expression is too large", _}} when length(alternatives) > 1 ->
        {a, b} = Enum.split(alternatives, div(length(alternatives), 2))
        compile_alternation(prefix, a, suffix, ignore_case) ++ compile_alternation(prefix, b, suffix, ignore_case)

      {:error, e} ->
        raise ArgumentError, "bad pattern #{inspect(prefix)}...: #{inspect(e)}"
    end
  end

  @doc false
  def finditer_multi([rx], s), do: finditer(rx, s)
  def finditer_multi(rxs, s), do: multi(Enum.map(rxs, &{&1, nil}), s, 0, [])

  # each part keeps its next match (nil: not searched yet, :none: no more matches); a kept match that starts at or
  # after `pos` is still that part's leftmost match from `pos`
  defp multi(parts, s, pos, acc) do
    parts =
      Enum.map(parts, fn
        {rx, :none} -> {rx, :none}
        {rx, m} when is_list(m) -> if m_start(m) >= pos, do: {rx, m}, else: {rx, search(rx, s, pos) || :none}
        {rx, nil} -> {rx, search(rx, s, pos) || :none}
      end)

    best =
      parts
      |> Enum.flat_map(fn
        {_, :none} -> []
        {_, m} -> [m]
      end)
      |> Enum.min_by(&m_start/1, fn -> nil end)

    case best do
      nil -> Enum.reverse(acc)
      m -> multi(parts, s, max(m_end(m), m_start(m) + 1), [m | acc])
    end
  end

  defp exact_mp(src, opts) do
    key = {__MODULE__, :exact, src, opts}

    case :persistent_term.get(key, nil) do
      nil ->
        {:ok, mp} = :re.compile(src, opts)
        :persistent_term.put(key, mp)
        mp

      mp ->
        mp
    end
  end

  @doc false
  # compile the look-around variant now (tests): :ok or {:error, reason}
  def check_exact(%{exact: nil}), do: :ok

  def check_exact(%{exact: src, opts: opts}) do
    case :re.compile(src, opts) do
      {:ok, _} -> :ok
      {:error, e} -> {:error, {src, e}}
    end
  end

  # characters that PCRE2's Unicode \w takes and Python's \w does not (combining marks, connector punctuation)
  # (an ASCII text has none: checked first with a byte scan, much cheaper than a regex run)
  defp risky?(s) do
    {non_ascii, mp} =
      case :persistent_term.get({__MODULE__, :risky}, nil) do
        nil ->
          {:ok, mp} = :re.compile("(?!_)[\\p{Mn}\\p{Pc}]", [:unicode])
          t = {:binary.compile_pattern(for(b <- 0x80..0xFF, do: <<b>>)), mp}
          :persistent_term.put({__MODULE__, :risky}, t)
          t

        t ->
          t
      end

    :binary.match(s, non_ascii) != :nomatch and :re.run(s, mp, [{:capture, :none}]) == :match
  end

  defp mp_for(%{exact: nil, fast: mp}, _s), do: mp

  defp mp_for(%{exact: src, fast: mp, opts: opts}, s) do
    if risky?(s), do: exact_mp(src, opts), else: mp
  end

  # A match is a list of `{byte_start, byte_length}` per group (`{-1, 0}`: the group did not take part).

  @doc false
  # Python `rx.search(s, pos)`: the first match starting at byte `pos` or later (look-behind still sees before `pos`).
  def search(rx, s, pos \\ 0) do
    case :re.run(s, mp_for(rx, s), [{:capture, :all, :index}, {:offset, pos}]) do
      {:match, m} -> m
      _ -> nil
    end
  end

  @doc false
  def found?(rx, s), do: :re.run(s, mp_for(rx, s), [{:capture, :none}]) == :match

  @doc false
  # Python `rx.match(s, pos)`: a match that starts exactly at byte `pos`.
  def match_at(rx, s, pos \\ 0) do
    case :re.run(s, mp_for(rx, s), [{:capture, :all, :index}, {:offset, pos}, :anchored]) do
      {:match, m} -> m
      _ -> nil
    end
  end

  @doc false
  # Python `rx.finditer(s)`: all non-overlapping matches (empty matches advance like Python 3.7+).
  def finditer(rx, s) do
    case :re.run(s, mp_for(rx, s), [:global, {:capture, :all, :index}]) do
      {:match, ms} -> ms
      _ -> []
    end
  end

  @doc false
  def group(m, s, i \\ 0) do
    case Enum.at(m, i) do
      {start, len} when start >= 0 -> binary_part(s, start, len)
      _ -> nil
    end
  end

  @doc false
  # Python `m.group(i) or ""`
  def group_str(m, s, i), do: group(m, s, i) || ""

  @doc false
  def m_start([{start, _} | _]), do: start
  @doc false
  def m_end([{start, len} | _]), do: start + len

  @doc false
  # Python `rx.sub(template, s)` with a template made by `template/1`.
  def sub(rx, s, template) do
    case finditer(rx, s) do
      [] ->
        s

      ms ->
        {parts, last} =
          Enum.reduce(ms, {[], 0}, fn m, {acc, last} ->
            start = m_start(m)
            repl = Enum.map(template, fn t -> if is_integer(t), do: group_str(m, s, t), else: t end)
            {[repl, binary_part(s, last, start - last) | acc], m_end(m)}
          end)

        IO.iodata_to_binary(Enum.reverse([binary_part(s, last, byte_size(s) - last) | parts]))
    end
  end

  @doc false
  # Parse a Python replacement string (`\g<1>`, `\1`, `\\`, `\n`, ...) into literal binaries and group numbers.
  def template(repl), do: template(repl, "", [])

  defp template("", "", acc), do: Enum.reverse(acc)
  defp template("", lit, acc), do: Enum.reverse([lit | acc])

  defp template("\\g<" <> rest, lit, acc) do
    [name, rest] = String.split(rest, ">", parts: 2)
    template(rest, "", [String.to_integer(name) | push(lit, acc)])
  end

  defp template(<<"\\", d1, d2, rest::binary>>, lit, acc) when d1 in ?0..?9 and d2 in ?0..?9,
    do: template(rest, "", [(d1 - ?0) * 10 + d2 - ?0 | push(lit, acc)])

  defp template(<<"\\", d, rest::binary>>, lit, acc) when d in ?0..?9, do: template(rest, "", [d - ?0 | push(lit, acc)])
  defp template("\\n" <> rest, lit, acc), do: template(rest, lit <> "\n", acc)
  defp template("\\t" <> rest, lit, acc), do: template(rest, lit <> "\t", acc)
  defp template("\\r" <> rest, lit, acc), do: template(rest, lit <> "\r", acc)
  defp template("\\\\" <> rest, lit, acc), do: template(rest, lit <> "\\", acc)

  defp template(<<"\\", c::utf8, rest::binary>>, lit, acc) do
    if c < 128 and (c in ?a..?z or c in ?A..?Z or c in ?0..?9),
      do: raise(ArgumentError, "unsupported escape in replacement #{inspect(rest)}"),
      else: template(rest, lit <> <<?\\, c::utf8>>, acc)
  end

  defp template(<<c::utf8, rest::binary>>, lit, acc), do: template(rest, lit <> <<c::utf8>>, acc)

  defp push("", acc), do: acc
  defp push(lit, acc), do: [lit | acc]

  # ---------- pattern translation ----------

  @doc false
  # Translate a Python pattern to PCRE2: `{native, exact}`, where `exact` (nil when the pattern has no \b or \B) spells
  # out the word boundaries with Python's word characters.
  def translate(pattern, ignore_case) do
    cs = String.to_charlist(pattern)
    {fast, exact, has_b} = tr(cs, ignore_case, [], [], false)
    {IO.iodata_to_binary(fast), if(has_b, do: IO.iodata_to_binary(exact))}
  end

  defp tr([], _ic, f, e, b), do: {Enum.reverse(f), Enum.reverse(e), b}

  defp tr([?\\, c | rest], ic, f, e, _b) when c in [?b, ?B] do
    exact = if c == ?b, do: @word_exact_b, else: @word_exact_nb
    tr(rest, ic, [<<?\\, c>> | f], [exact | e], true)
  end

  defp tr([?\\ | rest], ic, f, e, b) do
    {s, rest} = escape(rest, false, ic)
    tr(rest, ic, [s | f], [s | e], b)
  end

  defp tr([?[ | rest], ic, f, e, b) do
    {s, rest} = class(rest, ic)
    tr(rest, ic, [s | f], [s | e], b)
  end

  defp tr([?(, ??, ?# | rest], ic, f, e, b) do
    # comment group
    rest = rest |> Enum.drop_while(&(&1 != ?))) |> Enum.drop(1)
    tr(rest, ic, f, e, b)
  end

  defp tr([?(, ??, ?P, ?< | rest], ic, f, e, b) do
    {name, [?> | rest]} = Enum.split_while(rest, &(&1 != ?>))
    s = "(?P<" <> List.to_string(name) <> ">"
    tr(rest, ic, [s | f], [s | e], b)
  end

  defp tr([?(, ??, c | _], _ic, _f, _e, _b) when c in [?a, ?i, ?L, ?m, ?s, ?u, ?x, ?-],
    do: raise(ArgumentError, "inline flags are not supported")

  defp tr([?{ | rest] = all, ic, f, e, b) do
    case repetition(rest) do
      {q, rest} -> tr(rest, ic, [q | f], [q | e], b)
      nil -> tr(tl(all), ic, ["\\{" | f], ["\\{" | e], b)
    end
  end

  defp tr([?} | rest], ic, f, e, b), do: tr(rest, ic, ["\\}" | f], ["\\}" | e], b)

  defp tr([c | rest], true, f, e, b) when c in [?i, ?I, 0x130, 0x131] do
    s = "[" <> @i_class <> "]"
    tr(rest, true, [s | f], [s | e], b)
  end

  defp tr([c | rest], ic, f, e, b), do: tr(rest, ic, [<<c::utf8>> | f], [<<c::utf8>> | e], b)

  # `{m}`, `{m,}`, `{,n}`, `{m,n}` as Python reads them; nil if the brace is a literal
  defp repetition(cs) do
    {lo, cs} = Enum.split_while(cs, &(&1 in ?0..?9))

    {hi, comma, cs} =
      case cs do
        [?, | cs] ->
          {hi, cs} = Enum.split_while(cs, &(&1 in ?0..?9))
          {hi, true, cs}

        _ ->
          {lo, false, cs}
      end

    case cs do
      [?} | rest] when comma or lo != [] ->
        lo = if lo == [], do: ~c"0", else: lo

        q =
          cond do
            not comma -> "{#{lo}}"
            hi == [] -> "{#{lo},}"
            true -> "{#{lo},#{hi}}"
          end

        {q, rest}

      _ ->
        nil
    end
  end

  defp hex(cs, n) do
    {digits, rest} = Enum.split(cs, n)

    if length(digits) == n and Enum.all?(digits, &(&1 in ?0..?9 or &1 in ?a..?f or &1 in ?A..?F)) do
      {"\\x{" <> List.to_string(digits) <> "}", rest}
    else
      raise ArgumentError, "bad hex escape"
    end
  end

  # the escape after a backslash; `in_class` gives the form used inside [...]
  defp escape([], _in_class, _ic), do: raise(ArgumentError, "trailing backslash")

  defp escape([c | rest], in_class, ic) do
    digit = UnicodeTables.digit_class()
    space = UnicodeTables.space_class()

    s =
      case {c, in_class} do
        {?d, false} -> "[" <> digit <> "]"
        {?d, true} -> digit
        {?D, false} -> "[^" <> digit <> "]"
        {?w, false} -> "[" <> @word <> "]"
        {?w, true} -> @word
        {?W, false} -> "[^" <> @word <> "]"
        {?s, false} -> "[" <> space <> "]"
        {?s, true} -> space
        {?S, false} -> "[^" <> space <> "]"
        {?b, true} -> "\\x{8}"
        {?A, false} -> "\\A"
        {?Z, false} -> "\\z"
        {?n, _} -> "\\n"
        {?t, _} -> "\\t"
        {?r, _} -> "\\r"
        {?f, _} -> "\\x{C}"
        {?v, _} -> "\\x{B}"
        {?a, _} -> "\\x{7}"
        {?x, _} -> :hex2
        {?u, _} -> :hex4
        {?U, _} -> :hex8
        {d, false} when d in ?1..?9 -> <<?\\, d>>
        {c, _} when c > 127 -> if ic and c in [0x130, 0x131], do: :i_letter, else: <<c::utf8>>
        {c, _} when c in ?a..?z or c in ?A..?Z or c in ?0..?9 -> raise ArgumentError, "unsupported escape \\#{[c]}"
        {c, _} -> <<?\\, c>>
      end

    case s do
      :hex2 -> hex(rest, 2)
      :hex4 -> hex(rest, 4)
      :hex8 -> hex(rest, 8)
      :i_letter -> {if(in_class, do: @i_class, else: "[" <> @i_class <> "]"), rest}
      s -> {s, rest}
    end
  end

  # a character class after `[`; Python reads `]` first in the class as a literal and `[` inside as a literal
  defp class(cs, ic) do
    {neg, cs} = if match?([?^ | _], cs), do: {"^", tl(cs)}, else: {"", cs}
    {first, cs} = if match?([?] | _], cs), do: {["\\]"], tl(cs)}, else: {[], cs}
    {body, rest, members} = class_body(cs, first, [])
    extra = if ic and Enum.any?(members, &covers_i?/1), do: @i_class, else: ""
    {"[" <> neg <> IO.iodata_to_binary(Enum.reverse(body)) <> extra <> "]", rest}
  end

  defp class_body([], _acc, _m), do: raise(ArgumentError, "unterminated character class")
  defp class_body([?] | rest], acc, m), do: {acc, rest, m}

  defp class_body([?\\ | rest], acc, m) do
    {s, rest} = escape(rest, true, false)
    class_body(rest, [s | acc], m)
  end

  defp class_body([lo, ?-, hi | rest], acc, m) when hi != ?] and lo != ?\\ and hi != ?\\ do
    if lo > hi, do: raise(ArgumentError, "bad character range")
    class_body(rest, [[cls_char(lo), ?-, cls_char(hi)] | acc], [{lo, hi} | m])
  end

  defp class_body([c | rest], acc, m), do: class_body(rest, [cls_char(c) | acc], [{c, c} | m])

  defp cls_char(c) when c in [?[, ?&, ?~, ?|], do: <<?\\, c>>
  defp cls_char(c), do: <<c::utf8>>

  defp covers_i?({lo, hi}), do: Enum.any?([?I, ?i, 0x130, 0x131], &(&1 >= lo and &1 <= hi))

  # ---------- Python string helpers ----------

  @doc false
  # Python `re.escape` (3.7+): the same characters get a backslash.
  def escape(s) do
    for <<c::utf8 <- s>>, into: "" do
      if c in ~c"()[]{}?*+-|^$\\.&~# \t\n\r\v\f", do: <<?\\, c::utf8>>, else: <<c::utf8>>
    end
  end

  defp tables do
    case :persistent_term.get({__MODULE__, :tables}, nil) do
      nil ->
        c = fn p -> elem(:re.compile(p, [:unicode]), 1) end

        t = %{
          ws_run: c.("[" <> UnicodeTables.space_class() <> "]+"),
          strip: c.("\\A[" <> UnicodeTables.space_class() <> "]+|[" <> UnicodeTables.space_class() <> "]+\\z"),
          cased: c.("\\A[" <> UnicodeTables.cased_class() <> "]\\z"),
          ignorable: c.("\\A[" <> UnicodeTables.case_ignorable_class() <> "]\\z")
        }

        :persistent_term.put({__MODULE__, :tables}, t)
        t

      t ->
        t
    end
  end

  @doc false
  # Python `re.sub(r"\s+", " ", s)`.
  def collapse_ws(s), do: :re.replace(s, tables().ws_run, " ", [:global, {:return, :binary}])

  @doc false
  # Python `str.strip()`.
  def strip(s), do: :re.replace(s, tables().strip, "", [:global, {:return, :binary}])

  @doc false
  # Python `str.lower()`: full Unicode lowercase mapping, with the final sigma ("ΑΣ" -> "ας").
  def lower(s) do
    if String.contains?(s, "Σ"), do: lower_sigma(String.to_charlist(s)), else: String.downcase(s)
  end

  # Python's rule: U+03A3 becomes "ς" when, skipping case-ignorable characters, a cased character comes before it and
  # no cased character comes after it.
  defp lower_sigma(cps) do
    t = tables()
    is? = fn rx, c -> :re.run(<<c::utf8>>, rx, [{:capture, :none}]) == :match end

    # the first character that is not case-ignorable is cased
    cased_next? = fn list ->
      case Enum.drop_while(list, &is?.(t.ignorable, &1)) do
        [c | _] -> is?.(t.cased, c)
        [] -> false
      end
    end

    {res, _before} =
      cps
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {c, i}, {res, before} ->
        lowered =
          if c == 0x3A3 do
            if cased_next?.(before) and not cased_next?.(Enum.drop(cps, i + 1)), do: "ς", else: "σ"
          else
            String.downcase(<<c::utf8>>)
          end

        {[lowered | res], [c | before]}
      end)

    IO.iodata_to_binary(Enum.reverse(res))
  end

  @doc false
  # Python `html.unescape`: HTML5 named references with and without `;`, the longest known prefix of an unknown name
  # (`&ampx` -> `&x`), numeric references remapped or dropped the way browsers do.
  def html_unescape(s) do
    if String.contains?(s, "&"), do: unescape(s, []), else: s
  end

  defp unescape(s, acc) do
    case :binary.match(s, "&") do
      :nomatch ->
        IO.iodata_to_binary(Enum.reverse([s | acc]))

      {i, 1} ->
        before = binary_part(s, 0, i)
        after_ = binary_part(s, i + 1, byte_size(s) - i - 1)

        case charref_len(after_) do
          0 ->
            unescape(after_, ["&", before | acc])

          n ->
            body = binary_part(after_, 0, n)
            unescape(binary_part(after_, n, byte_size(after_) - n), [replace_ref(body), before | acc])
        end
    end
  end

  # length in bytes of `#[0-9]+;?|#[xX][0-9a-fA-F]+;?|[^\t\n\f <&#;]{1,32};?` at the start, 0 if none
  defp charref_len("#" <> rest) do
    case count_while(rest, &(&1 in ?0..?9)) do
      0 ->
        case rest do
          <<x, hexs::binary>> when x in [?x, ?X] ->
            case count_while(hexs, &(&1 in ?0..?9 or &1 in ?a..?f or &1 in ?A..?F)) do
              0 -> 0
              n -> semi(hexs, n, 2 + n)
            end

          _ ->
            0
        end

      n ->
        semi(rest, n, 1 + n)
    end
  end

  defp charref_len(s) do
    n = name_len(s, 0, 0)
    if n == 0, do: 0, else: semi(s, n, n)
  end

  defp semi(s, pos, n) do
    case s do
      <<_::binary-size(^pos), ";", _::binary>> -> n + 1
      _ -> n
    end
  end

  defp count_while(<<c, rest::binary>>, f), do: if(f.(c), do: 1 + count_while(rest, f), else: 0)
  defp count_while(<<>>, _f), do: 0

  defp name_len(_s, 32, bytes), do: bytes

  defp name_len(<<c::utf8, rest::binary>>, count, bytes) when c not in [?\t, ?\n, ?\f, ?\s, ?<, ?&, ?#, ?;],
    do: name_len(rest, count + 1, bytes + byte_size(<<c::utf8>>))

  defp name_len(_s, _count, bytes), do: bytes

  defp replace_ref("#" <> num) do
    num = String.trim_trailing(num, ";")

    n =
      case num do
        <<x, hexs::binary>> when x in [?x, ?X] -> String.to_integer(hexs, 16)
        _ -> String.to_integer(num)
      end

    ent = GunsNPrices.Data.entities()

    cond do
      Map.has_key?(ent.invalid_charrefs, n) -> ent.invalid_charrefs[n]
      n in 0xD800..0xDFFF or n > 0x10FFFF -> "�"
      MapSet.member?(ent.invalid_codepoints, n) -> ""
      true -> <<n::utf8>>
    end
  end

  defp replace_ref(name) do
    html5 = GunsNPrices.Data.entities().html5

    case html5 do
      %{^name => v} ->
        v

      _ ->
        # the longest known name that the reference starts with
        cps = String.to_charlist(name)

        found =
          Enum.find_value((length(cps) - 1)..2//-1, fn x ->
            prefix = List.to_string(Enum.take(cps, x))
            if v = html5[prefix], do: v <> List.to_string(Enum.drop(cps, x))
          end)

        found || "&" <> name
    end
  end

  @doc false
  # Value of a decimal digit of any script (what Python's `\d` matches and `int()` reads).
  def digit_value(c) when c in ?0..?9, do: c - ?0

  def digit_value(c) do
    zeros = UnicodeTables.digit_zeros()
    zero = find_zero(zeros, c, 0, tuple_size(zeros) - 1, nil)
    if zero != nil and c - zero < 10, do: c - zero
  end

  defp find_zero(_z, _c, lo, hi, best) when lo > hi, do: best

  defp find_zero(z, c, lo, hi, best) do
    mid = div(lo + hi, 2)
    v = elem(z, mid)
    if v <= c, do: find_zero(z, c, mid + 1, hi, v), else: find_zero(z, c, lo, mid - 1, best)
  end

  @doc false
  # Python `int(s)` for a string of decimal digits of any script.
  def int(s) do
    s |> String.to_charlist() |> Enum.reduce(0, fn c, acc -> acc * 10 + digit_value(c) end)
  end

  @doc false
  # Python `float(s)` for digits (any script) with an optional decimal point.
  def float(s) do
    ascii = for <<c::utf8 <- s>>, into: "", do: if(c == ?., do: ".", else: <<digit_value(c) + ?0>>)
    {f, ""} = Float.parse(ascii)
    f
  end

  @doc false
  # Python `round(x, 4)`: the exact binary value rounded half to even at 4 decimals, then the nearest float.
  def round4(x) when is_float(x) do
    <<sign::1, exp::11, mant::52>> = <<x::float>>
    {m, e} = if exp == 0, do: {mant, -1074}, else: {mant + (1 <<< 52), exp - 1075}
    n = m * 10_000

    q =
      if e >= 0 do
        n <<< e
      else
        d = 1 <<< -e
        {q, r} = {div(n, d), rem(n, d)}

        cond do
          2 * r > d -> q + 1
          2 * r < d -> q
          rem(q, 2) == 1 -> q + 1
          true -> q
        end
      end

    v = q / 10_000
    if sign == 1, do: -v, else: v
  end

  @doc false
  # Number of code points before byte offset `byte` (a Python string index).
  def cp_index(s, byte), do: s |> binary_part(0, byte) |> cp_count()

  @doc false
  def cp_count(s), do: for(<<_::utf8 <- s>>, reduce: 0, do: (n -> n + 1))

  @doc false
  # Byte offset `n` code points before byte offset `byte`, stopping at 0 (Python `s[max(0, i - n):i]`).
  def back_cps(s, byte, n) do
    prefix = binary_part(s, 0, byte)
    count = cp_count(prefix)
    skip = max(count - n, 0)
    byte_size(prefix) - byte_size(drop_cps(prefix, skip))
  end

  @doc false
  # Python `s[:n]` (code points).
  def take_cps(s, n), do: binary_part(s, 0, byte_size(s) - byte_size(drop_cps(s, n)))

  defp drop_cps(s, 0), do: s
  defp drop_cps(<<_::utf8, rest::binary>>, n), do: drop_cps(rest, n - 1)
  defp drop_cps(<<>>, _n), do: <<>>
end
