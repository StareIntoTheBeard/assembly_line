import Config

if Mix.env() == :test do
  config :assembly_line, AssemblyLine.PhoneBook, %{
    test: %{
      basic: %{
        adapter: AssemblyLine.Adapters.TestAdapter,
        route: %{
          disable_conversation_recording: true
        }
      }
    }
  }
end
