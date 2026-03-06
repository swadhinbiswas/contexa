defmodule Contexa.MixProject do
  use Mix.Project

  @version "1.1.2"
  @source_url "https://github.com/swadhinbiswas/Cortexa"

  def project do
    [
      app: :contexa,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "readme",
        extras: ["README.md", "LICENSE"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.9"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Git-inspired context management for LLM agents — COMMIT, BRANCH, MERGE,
    and CONTEXT operations over a persistent versioned memory workspace.
    Based on arXiv:2508.00031.
    """
  end

  defp package do
    [
      name: "contexa",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Paper" => "https://arxiv.org/abs/2508.00031"
      },
      maintainers: ["Swadhin Biswas"],
      files: ~w(lib mix.exs README.md LICENSE)
    ]
  end
end
