defmodule AssemblyLine.Assigner do
  defmacro __using__(_) do
    quote do
      @before_compile AssemblyLine.Assigner
      Module.register_attribute(__MODULE__, :__prompt_assigns__, accumulate: true)
      Module.register_attribute(__MODULE__, :__prompt_outputs__, accumulate: true)

      import AssemblyLine.Assigner, only: [attr: 2, return: 1, return: 2]
      import Phoenix.Component, only: [sigil_H: 2]
    end
  end

  defmacro attr(name, opts \\ []) do
    quote do
      @__prompt_assigns__ {unquote(name), unquote(opts)}
    end
  end

  defmacro return(name, _opts \\ []) do
    quote do
      @__prompt_outputs__ {unquote(name)}
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __prompt_assigns__, do: @__prompt_assigns__ || []
      def __prompt_outputs__, do: @__prompt_outputs__ || []

      # Validation function to ensure required assigns exist
      def validate_assigns(assigns, opts) do
        verbose = Keyword.get(opts, :verbose, false)
        if verbose, do: dbg(assigns)

        compiler = Keyword.get(opts, :compiler, false)

        required_prompt_assigns =
          Enum.filter(@__prompt_assigns__, fn {_name, opts} ->
            Keyword.get(opts, :required, false)
          end)
          |> Enum.map(fn {name, _opts} -> name end)

        missing_prompt_assigns =
          Enum.filter(required_prompt_assigns, fn attr ->
            not Map.has_key?(assigns, attr)
          end)

        if missing_prompt_assigns != [] do
          raise "Missing required assigns:  #{inspect(missing_prompt_assigns)} on step #{inspect(__MODULE__)}"
        end

        assigns =
          if compiler do
            assigns
          else
            Map.filter(assigns, fn {assign, value} -> not is_nil(value) end)
          end

        default_prompt_assigns =
          Enum.filter(@__prompt_assigns__, fn {_name, opts} ->
            Keyword.get(opts, :default, false)
          end)
          |> Enum.reduce(%{}, fn {name, opts}, acc ->
            Map.put(acc, name, Keyword.get(opts, :default))
          end)

        default_prompt_outputs =
          Enum.reduce(@__prompt_outputs__, %{}, fn {name}, acc ->
            Map.put(acc, name, nil)
          end)

        Map.merge(default_prompt_outputs, default_prompt_assigns)
        |> Map.merge(assigns)
      end
    end
  end
end
