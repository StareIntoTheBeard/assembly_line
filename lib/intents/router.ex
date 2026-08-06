defmodule Intents.Router do
  defmacro __using__(_) do
    quote do
      Module.register_attribute(__MODULE__, :routes, accumulate: true)
      import Intents.Router, only: [defintent: 2]
      @before_compile Intents.Router
    end
  end

  defmacro defintent(route_name, do: body) do
    quote do
      @routes unquote(Macro.escape(route_name))
      def route(unquote(route_name)), do: unquote(body)
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def __routes__, do: @routes

      def route_guide(actions) do
        Enum.filter(@routes, fn route ->
          if route in actions, do: route
        end)
        |> Enum.map(fn vetted_route ->
          {_intent_module, _intent_function, %{prompt: prompt}} = __MODULE__.route(vetted_route)
          "#{vetted_route} - #{prompt}"
        end)
      end
    end
  end
end
