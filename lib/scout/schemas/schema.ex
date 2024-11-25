defmodule Scout.Schemas.Schema do
  @moduledoc """
  Top-level schema specification that represents a complete Ecto schema
  """
  use Flint.Schema, extensions: Flint.default_extensions() ++ [Instructor.Instruction]
  alias Scout.Schemas.{Field, Embed}

  @system_prompt """
  You are a schema design expert. Given an HTML document, analyze its structure and content
  to infer an appropriate Ecto schema that could represent this data.

  Prioritize making the schema relevant for web-scraping tasks, therefore do not overly
  represent fields in the page that would not be relevant to web scraping.
  You must toe the balance between making field names too specific to the particular page while
  still having it be generic enough to generalize.

  You should proioritize repeated fields / embeds and structure your schema logically
  according to the structure of the page, while maintaining focus on the main content
  of the page. Keep in mind this information will be used to generate reports, APIs,
  lists, etc. in downstream tasks, so make the schema have fields / emebeds relevant to
  those tasks.

  The schema should not overfit the page, meaning that it should not have so many granular fields
  that it essentially copies the HTML.

  Return a complete schema specification following these rules:
  - Use PascalCase for module names
  - Provide clear descriptions
  - Structure complex data as embedded schemas rather than array of maps
  """
  @template """
  Analyze this content and create a complete schema specification.
  Source Type: <%= @type %>
  Content Body:
  <%= @content %>
  """
  embedded_schema do
    field!(:module_name, :string, map: Module.concat([String.capitalize(module_name)]))
    field(:description, :string)
    embeds_many(:fields, Field)
    embeds_many(:embeds, Embed)
  end

  @doc """
  Generates an Ecto schema module from a schema specification.
  """
  def generate(%__MODULE__{} = spec) do
    quote do
      embedded_schema do
        # Regular fields
        unquote_splicing(Enum.map(spec.fields, &Field.generate/1))

        # Embedded schemas
        unquote_splicing(Enum.map(spec.embeds, &Embed.generate/1))
      end
    end
  end
end
