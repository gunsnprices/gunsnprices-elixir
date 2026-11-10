defmodule GunsNPrices.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/gunsnprices/gunsnprices-elixir"

  def project do
    [
      app: :gunsnprices,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Parse firearm and ammunition product titles: brand, model, caliber, magazine capacity, barrel length, " <>
          "rounds per box, cost per round. The rules and data behind gunsnprices.com; same results as the Python package.",
      package: package(),
      docs: docs(),
      name: "GunsNPrices",
      source_url: @source_url,
      homepage_url: "https://gunsnprices.com"
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp deps do
    [
      # only to derive Jason.Encoder on the result structs when the host application uses Jason
      {:jason, "~> 1.4", optional: true},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT", "CC-BY-4.0"],
      links: %{"Website" => "https://gunsnprices.com", "GitHub" => @source_url},
      files: ~w(lib priv/data/models.json priv/data/calibers.json priv/data/entities.json tools/gen_tables.py
                mix.exs README.md CHANGELOG.md LICENSE LICENSE-DATA .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: "https://gunsnprices.com",
      extras: ["README.md", "CHANGELOG.md", "LICENSE", "LICENSE-DATA"],
      groups_for_modules: [Results: [GunsNPrices.ProductInfo, GunsNPrices.ModelMatch, GunsNPrices.Caliber]]
    ]
  end
end
