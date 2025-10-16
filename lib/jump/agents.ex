defmodule Jump.Agents do
  @moduledoc """
  The Agents context handles AI agent instructions and rules.
  """

  import Ecto.Query, warn: false
  alias Jump.Repo

  alias Jump.Agents.Instruction

  def list_instructions(user_id) do
    Instruction
    |> where([i], i.user_id == ^user_id)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  def list_enabled_instructions(user_id) do
    Instruction
    |> where([i], i.user_id == ^user_id and i.enabled == true)
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  def get_instruction!(id), do: Repo.get!(Instruction, id)

  def create_instruction(attrs \\ %{}) do
    %Instruction{}
    |> Instruction.changeset(attrs)
    |> Repo.insert()
  end

  def update_instruction(%Instruction{} = instruction, attrs) do
    instruction
    |> Instruction.changeset(attrs)
    |> Repo.update()
  end

  def delete_instruction(%Instruction{} = instruction) do
    Repo.delete(instruction)
  end

  def change_instruction(%Instruction{} = instruction, attrs \\ %{}) do
    Instruction.changeset(instruction, attrs)
  end

  def enable_instruction(%Instruction{} = instruction) do
    update_instruction(instruction, %{enabled: true})
  end

  def disable_instruction(%Instruction{} = instruction) do
    update_instruction(instruction, %{enabled: false})
  end

  def get_enabled_instructions_for_user(user_id) do
    list_enabled_instructions(user_id)
  end
end
