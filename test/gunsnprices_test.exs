defmodule GunsNPricesTest do
  use ExUnit.Case, async: true
  doctest GunsNPrices

  alias GunsNPrices.Py

  # rules compile on first use, so a pattern no golden title reaches would only fail in use: check them all here,
  # including the look-around variants used for titles with combining marks
  test "every dictionary rule compiles" do
    rules = GunsNPrices.Models.all_rules()
    assert length(rules) > 2900
    assert Enum.reject(rules, &(Py.check_exact(&1) == :ok)) == []
  end

  test "caliber spelling table matches the Python package" do
    table = GunsNPrices.Calibers.spellings()
    # the Python package builds 946 spellings from the same data
    assert length(table) == 946
    lookup = Map.new(table)
    assert lookup["9mm"] == "9x19mmparabellum"
    assert lookup["300blk"] == "300aacblackout"
    assert lookup["12ga"] == "12gauge"
    assert length(GunsNPrices.list_calibers()) == 293
  end

  test "Python regex semantics" do
    rx = Py.compile(~S"(?<![\d.])(\d{1,3})\s*\+\s*1(?!\d)")
    assert Py.search(rx, "x 15+1 y") |> Py.group("x 15+1 y", 1) == "15"
    assert Py.search(rx, "115+12") == nil
    # $ also before a final newline; \Z only at the very end
    assert Py.found?(Py.compile(~S"^\d+\s?g$"), "12g\n")
    refute Py.found?(Py.compile(~S"^\d+\s?g$"), "12g\n\n")
    refute Py.found?(Py.compile(~S"g\Z"), "12g\n")
    # \s covers U+001C..U+001F like Python, but not U+180E
    assert Py.found?(Py.compile(~S"a\sb"), "a\x1Cb")
    refute Py.found?(Py.compile(~S"a\sb"), "a᠎b")
    # \w is letters, digits and _ (no combining marks), and \b follows it
    refute Py.found?(Py.compile(~S"\w"), "́")
    assert Py.found?(Py.compile(~S"a\b"), "á")
    refute Py.found?(Py.compile(~S"a\b"), "ab")
    # re.I: "i" also matches dotless and dotted I
    assert Py.found?(Py.compile("sarsilmaz", true), "sarsılmaz")
    assert Py.found?(Py.compile("[a-z]", true), "İ")
    refute Py.found?(Py.compile("[^a-z]", true), "ı")
    # literal braces, {,n}
    assert Py.found?(Py.compile("a{,2}b{"), "aab{")
    # digits of any script
    assert Py.found?(Py.compile(~S"^\d+$"), "١٥")
    assert Py.int("١٥") == 15
    assert Py.float("4.02") == 4.02
    t = Py.template(~S"glock \g<2> gen \g<1>")
    assert Py.sub(Py.compile(~S"\bglock gen\.? ?([1-6]) (\d{2})\b", true), "glock gen 5 19 mos", t) == "glock 19 gen 5 mos"
  end

  test "Python string helpers" do
    assert Py.collapse_ws(" a \t\x1Cb  ") == " a b "
    assert Py.strip("\x1F a 　") == "a"
    assert Py.escape("a b-c&d~e#f.g") == ~S"a\ b\-c\&d\~e\#f\.g"
    assert Py.lower("ΑΣ ΟΔΟΣ.") == "ας οδος."
    assert Py.lower("ΣΑ") == "σα"
    assert Py.lower("İ") == "i̇"
    assert Py.html_unescape("26&quot; &amp;amp; &ampx &#x2B;1 &#128; &#0; &bogus;") == "26\" &amp; &x +1 € � &bogus;"
    assert Py.cp_index("a×b", 3) == 2
    assert Py.back_cps("ab×cd", 5, 2) == 2
    assert Py.back_cps("abc", 2, 10) == 0
  end

  test "rounding is half to even on the exact value, like Python's round()" do
    # 0.03125 is exact in binary: Python rounds it to 0.0312
    assert Py.round4(0.03125) == 0.0312
    assert Py.round4(0.03135) == 0.0314
    assert GunsNPrices.cost_per_round(1.25, 40) == 0.0312
    assert GunsNPrices.cost_per_round(449.99, 1000) == 0.45
    assert GunsNPrices.cost_per_round(0, 10) == nil
  end

  test "options and odd input" do
    assert GunsNPrices.parse_title(nil).kind == :firearm
    assert GunsNPrices.parse_title("Federal 9mm 50/Box", kind: "firearm").kind == :firearm
    assert GunsNPrices.parse_title(<<"Glock 19 ", 255, "9mm">>).model.model == "Glock 19"
    assert_raise ArgumentError, fn -> GunsNPrices.parse_title("x", kind: :pistol) end
    assert_raise ArgumentError, fn -> GunsNPrices.parse_title("x", color: "red") end
  end

  test "results encode to JSON with the Python field names" do
    json = GunsNPrices.parse_title("Hornady 6.5 CM 140gr ELD Match 20rds") |> JSON.encode!() |> JSON.decode!()
    assert json["kind"] == "ammo"
    assert json["caliber"] == %{"id" => "6-5mmcreedmoor", "name" => "6.5mm Creedmoor", "type" => "rifle",
             "url" => "https://gunsnprices.com/ammo/rifle-ammo/6-5mm-creedmoor"}
    assert json["rounds"] == 20
    assert Map.keys(json) |> Enum.sort() ==
             ~w(barrel_length brand caliber calibers capacity cost_per_round kind model rounds title)
  end
end
