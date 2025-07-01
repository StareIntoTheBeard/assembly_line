defmodule AssemblyLine.Changeset do
  defmacro __using__(through: revisable_schema) do
    quote do
      import AssemblyLine.Changeset
      @__repo__ List.first(Application.get_env(Mix.Project.config()[:app], :ecto_repos))
    end
  end

  defmacro validates_acceptable_to_ai(changeset, check_ai \\ false) do
    quote bind_quoted: [changeset: changeset, check_ai: check_ai] do
      changeset =
        if check_ai && changeset.valid? do
          values = Ecto.Changeset.apply_changes(changeset)

          event =
            AssemblyLine.init()
            |> AssemblyLine.update_assigns(%{prompt_to_check: inspect(values)})
            |> AssemblyLine.Changeset.CheckService.execute()

          event.response.content
          |> Jason.decode!()
          |> Enum.into([])
          |> Enum.reduce(changeset, fn {key, value}, changeset_acc ->
            if String.match?(value, ~r/.*INVALID.*/) do
              Ecto.Changeset.add_error(
                changeset_acc,
                String.to_existing_atom(key),
                "rejected by AI"
              )
            else
              changeset_acc
            end
          end)
        else
          changeset
        end

      changeset
    end
  end
end
