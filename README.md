# AssemblyLine

The current AI infrastructure that underlies microdose.ai

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `assembly_line` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:assembly_line, "~> 0.1.0"}
  ]
end
```

## Current Feature Set
* Predefined pipelines with predefined steps
* Arbitrary pipelines with predefined steps
* Multi-model, multi-cloud support
  * OpenAI
  * Bedrock Foundation Models
    * Claude
  * OpenAI Assistants
  * Bedrock Agents
* Async steps
* LiveView support
* Model/Agent routing via PhoneBook
* Conversation auditing
* Basic training jobs with tagging
* MongoDB Support

## Planned Features
* Pipeline planning from a prompt
* Arbitrary pipelines with adhoc steps
* Job monitoring
* Query management
* Job queues/restarts
* Alternate models on a restarted job
* Additional models support
* Ability to select training method
* Ability to review/alter tagging
* Other data connectors
* API connectors
* UI (build a product lol)