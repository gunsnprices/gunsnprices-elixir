defmodule GunsNPrices.GoldenTest do
  # Regression test: parse_title on 1,150 real store titles must give the recorded answers. golden.jsonl is the same file
  # the Python package (tests/golden.jsonl) and the JavaScript package (test/golden.jsonl) use.
  use ExUnit.Case, async: true

  @golden Path.expand("golden.jsonl", __DIR__)
  @external_resource @golden

  defp compact(info) do
    m = info.model

    %{
      "kind" => Atom.to_string(info.kind),
      "brand" => info.brand,
      "model" => m && [m.family, m.model, m.generation, m.configs, m.features, Atom.to_string(m.source)],
      "calibers" => Enum.map(info.calibers, & &1.id),
      "capacity" => info.capacity,
      "barrel_length" => info.barrel_length,
      "rounds" => info.rounds,
      "cost_per_round" => info.cost_per_round
    }
  end

  test "1,150 store titles parse exactly like the Python package" do
    cases =
      @golden
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&JSON.decode!/1)

    assert length(cases) == 1150

    failures =
      for %{"args" => args, "expected" => expected} <- cases,
          opts = for({k, v} <- args, k != "title", do: {String.to_existing_atom(k), v}),
          got = compact(GunsNPrices.parse_title(args["title"], opts)),
          # == compares numbers by value (26 == 26.0), like Python
          got != expected do
        "#{args["title"]}\n    expected #{inspect(expected)}\n    got      #{inspect(got)}"
      end

    IO.puts("\ngolden: #{1150 - length(failures)}/1150 titles parse exactly like the Python package")
    assert failures == [], "#{length(failures)} mismatches:\n" <> Enum.join(Enum.take(failures, 20), "\n")
  end
end
