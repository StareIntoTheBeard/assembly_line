defmodule AssemblyLine.Changeset.Step.CheckService do
  use AssemblyLine.Step

  attr(:prompt_to_check, default: "")

  def prompt(assigns) do
    dbg assigns.prompt_to_check
    ~A"""
      values: {@prompt_to_check}
      Check to see if this has any vulgarity, curse words, swears, slurs or hate speech.
      A field is INVALID if contains vulgarity, curse words, swears, slurs or hate speech.
      A field is VALID if it does not contain vulgarity or hate speech.
      If a field has a list or array, either the whole list is valid or the whole list is invalid. Do not return validity in an array or list.
      Return ONLY valid JSON with keys as the FIELD NAME and "VALID" or "INVALID" as values as applicable.
    """
  end

  def after_step(event) do
    dbg event.response
    event
  end

  def dial_agent(), do: {:foundation, :bedrock_gpt120}
end
