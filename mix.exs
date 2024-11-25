defmodule Scout.MixProject do
  use Mix.Project

  def project do
    [
      app: :scout,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:req, "~> 0.5"},
      {:flint, github: "acalejos/flint", override: true},
      {:instructor, github: "acalejos/instructor_ex"},
      {:typed_ecto_schema, "~> 0.4.1"}
    ]
  end
end
