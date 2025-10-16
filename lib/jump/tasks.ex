defmodule Jump.Tasks do
  @moduledoc """
  The Tasks context handles durable workflow tasks.
  """

  import Ecto.Query, warn: false
  alias Jump.Repo

  alias Jump.Tasks.Task

  def list_tasks(user_id) do
    Task
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  def list_tasks_by_status(user_id, status) do
    Task
    |> where([t], t.user_id == ^user_id and t.status == ^status)
    |> order_by([t], asc: t.inserted_at)
    |> Repo.all()
  end

  def get_task!(id), do: Repo.get!(Task, id)

  def get_task_by_correlation_key(user_id, correlation_key) do
    Repo.get_by(Task, user_id: user_id, correlation_key: correlation_key)
  end

  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  def delete_task(%Task{} = task) do
    Repo.delete(task)
  end

  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  def update_task_status(%Task{} = task, status) do
    update_task(task, %{status: status})
  end

  def mark_task_running(%Task{} = task) do
    update_task(task, %{status: "running"})
  end

  def mark_task_done(%Task{} = task, result) do
    update_task(task, %{status: "done", result: result})
  end

  def mark_task_failed(%Task{} = task, error) do
    update_task(task, %{status: "failed", error: error})
  end

  def mark_task_waiting(%Task{} = task, state) do
    update_task(task, %{status: "waiting", state: state})
  end

  def get_pending_tasks(user_id) do
    Task
    |> where([t], t.user_id == ^user_id and t.status in ["queued", "waiting"])
    |> order_by([t], asc: t.inserted_at)
    |> Repo.all()
  end

  def find_or_create_task(user_id, kind, correlation_key, attrs \\ %{}) do
    case get_task_by_correlation_key(user_id, correlation_key) do
      nil ->
        create_task(
          Map.merge(attrs, %{
            user_id: user_id,
            kind: kind,
            correlation_key: correlation_key
          })
        )

      task ->
        {:ok, task}
    end
  end
end
