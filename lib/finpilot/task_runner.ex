defmodule Finpilot.TaskRunner do
  @moduledoc """
  The TaskRunner context.
  """

  import Ecto.Query, warn: false
  alias Finpilot.Repo

  alias Finpilot.TaskRunner.Task

  @doc """
  Returns the list of tasks.

  ## Examples

      iex> list_tasks()
      [%Task{}, ...]

  """
  def list_tasks do
    Repo.all(Task)
  end

  @doc """
  Gets a single task.

  Raises `Ecto.NoResultsError` if the Task does not exist.

  ## Examples

      iex> get_task!(123)
      %Task{}

      iex> get_task!(456)
      ** (Ecto.NoResultsError)

  """
  def get_task!(id), do: Repo.get!(Task, id)

  @doc """
  Gets a single task.

  Returns `{:ok, task}` if the task exists, `{:error, :not_found}` otherwise.

  ## Examples

      iex> get_task(123)
      {:ok, %Task{}}

      iex> get_task(456)
      {:error, :not_found}

  """
  def get_task(id) do
    case Repo.get(Task, id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  @doc """
  Creates a task.

  ## Examples

      iex> create_task(%{field: value})
      {:ok, %Task{}}

      iex> create_task(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a task.

  ## Examples

      iex> update_task(task, %{field: new_value})
      {:ok, %Task{}}

      iex> update_task(task, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a task.

  ## Examples

      iex> delete_task(task)
      {:ok, %Task{}}

      iex> delete_task(task)
      {:error, %Ecto.Changeset{}}

  """
  def delete_task(%Task{} = task) do
    Repo.delete(task)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking task changes.

  ## Examples

      iex> change_task(task)
      %Ecto.Changeset{data: %Task{}}

  """
  def change_task(%Task{} = task, attrs \\ %{}) do
    Task.changeset(task, attrs)
  end

  alias Finpilot.TaskRunner.TaskStage

  @doc """
  Returns the list of task_stages.

  ## Examples

      iex> list_task_stages()
      [%TaskStage{}, ...]

  """
  def list_task_stages do
    Repo.all(TaskStage)
  end

  @doc """
  Gets a single task_stage.

  Raises `Ecto.NoResultsError` if the Task stage does not exist.

  ## Examples

      iex> get_task_stage!(123)
      %TaskStage{}

      iex> get_task_stage!(456)
      ** (Ecto.NoResultsError)

  """
  def get_task_stage!(id), do: Repo.get!(TaskStage, id)

  @doc """
  Creates a task_stage.

  ## Examples

      iex> create_task_stage(%{field: value})
      {:ok, %TaskStage{}}

      iex> create_task_stage(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_task_stage(attrs \\ %{}) do
    %TaskStage{}
    |> TaskStage.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a task_stage.

  ## Examples

      iex> update_task_stage(task_stage, %{field: new_value})
      {:ok, %TaskStage{}}

      iex> update_task_stage(task_stage, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_task_stage(%TaskStage{} = task_stage, attrs) do
    task_stage
    |> TaskStage.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a task_stage.

  ## Examples

      iex> delete_task_stage(task_stage)
      {:ok, %TaskStage{}}

      iex> delete_task_stage(task_stage)
      {:error, %Ecto.Changeset{}}

  """
  def delete_task_stage(%TaskStage{} = task_stage) do
    Repo.delete(task_stage)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking task_stage changes.

  ## Examples

      iex> change_task_stage(task_stage)
      %Ecto.Changeset{data: %TaskStage{}}

  """
  def change_task_stage(%TaskStage{} = task_stage, attrs \\ %{}) do
    TaskStage.changeset(task_stage, attrs)
  end

  alias Finpilot.TaskRunner.Instruction

  @doc """
  Returns the list of instructions.

  ## Examples

      iex> list_instructions()
      [%Instruction{}, ...]

  """
  def list_instructions do
    Repo.all(Instruction)
  end

  @doc """
  Gets a single instruction.

  Raises `Ecto.NoResultsError` if the Instruction does not exist.

  ## Examples

      iex> get_instruction!(123)
      %Instruction{}

      iex> get_instruction!(456)
      ** (Ecto.NoResultsError)

  """
  def get_instruction!(id), do: Repo.get!(Instruction, id)

  @doc """
  Creates a instruction.

  ## Examples

      iex> create_instruction(%{field: value})
      {:ok, %Instruction{}}

      iex> create_instruction(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_instruction(attrs \\ %{}) do
    %Instruction{}
    |> Instruction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a instruction.

  ## Examples

      iex> update_instruction(instruction, %{field: new_value})
      {:ok, %Instruction{}}

      iex> update_instruction(instruction, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_instruction(%Instruction{} = instruction, attrs) do
    instruction
    |> Instruction.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a instruction.

  ## Examples

      iex> delete_instruction(instruction)
      {:ok, %Instruction{}}

      iex> delete_instruction(instruction)
      {:error, %Ecto.Changeset{}}

  """
  def delete_instruction(%Instruction{} = instruction) do
    Repo.delete(instruction)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking instruction changes.

  ## Examples

      iex> change_instruction(instruction)
      %Ecto.Changeset{data: %Instruction{}}

  """
  def change_instruction(%Instruction{} = instruction, attrs \\ %{}) do
    Instruction.changeset(instruction, attrs)
  end
end
