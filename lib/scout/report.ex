defmodule Scout.Report do
  defstruct [:spec, :raw, :response_model]

  @type t() :: %__MODULE__{
          spec: Scout.Schemas.Schema.t(),
          raw: binary()
        }
end
