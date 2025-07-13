defmodule Finpilot.Workers.ToolExecutor do
  @moduledoc """
  Handles execution of AI-selected tools within the TaskRunner system.
  This module provides a centralized way to execute various tools
  that the AI can call to complete tasks.
  """

  # alias Finpilot.Services.Gmail  # TODO: Uncomment when Gmail service is implemented
  alias Finpilot.TaskRunner
  alias Finpilot.Accounts
  require Logger

  @doc """
  Execute a tool with given parameters for a specific user.
  """
  def execute_tool(tool_name, params, user_id) do
    Logger.info("Executing tool: #{tool_name} for user: #{user_id}")
    
    case tool_name do
      "send_email" -> execute_send_email(params, user_id)
      "schedule_meeting" -> execute_schedule_meeting(params, user_id)
      "update_crm" -> execute_update_crm(params, user_id)
      "create_task" -> execute_create_task(params, user_id)
      "update_task_stage" -> execute_update_task_stage(params, user_id)
      "wait_for_response" -> execute_wait_for_response(params, user_id)
      "create_assistant_message" -> execute_create_assistant_message(params, user_id)
      "create_system_notification" -> execute_create_system_notification(params, user_id)
      _ -> {:error, "Unknown tool: #{tool_name}"}
    end
  end

  # Send email using Gmail service
  defp execute_send_email(params, user_id) do
    with {:ok, _user} <- get_user(user_id),
         {:ok, _} <- validate_email_params(params) do
      
      # Prepare email data
      email_data = %{
        to: params["to"],
        subject: params["subject"],
        body: params["body"],
        cc: params["cc"] || [],
        bcc: params["bcc"] || []
      }
      
      # TODO: Implement actual email sending via Gmail service
      # Gmail.send_email(user, email_data)
      
      Logger.info("Email would be sent: #{inspect(email_data)}")
      {:ok, %{action: "email_sent", recipients: params["to"], subject: params["subject"]}}
    else
      error -> error
    end
  end

  # Schedule meeting using Calendar service
  defp execute_schedule_meeting(params, user_id) do
    with {:ok, _user} <- get_user(user_id),
         {:ok, _} <- validate_meeting_params(params) do
      
      # Prepare meeting data
      meeting_data = %{
        title: params["title"],
        attendees: params["attendees"],
        start_time: params["start_time"],
        end_time: params["end_time"],
        description: params["description"],
        location: params["location"]
      }
      
      # TODO: Implement actual meeting scheduling via Calendar service
      # Calendar.schedule_meeting(user, meeting_data)
      
      Logger.info("Meeting would be scheduled: #{inspect(meeting_data)}")
      {:ok, %{action: "meeting_scheduled", title: params["title"], attendees: params["attendees"]}}
    else
      error -> error
    end
  end

  # Update CRM system
  defp execute_update_crm(params, user_id) do
    with {:ok, _user} <- get_user(user_id),
         {:ok, _} <- validate_crm_params(params) do
      
      # Prepare CRM data
      crm_data = %{
        contact_email: params["contact_email"],
        action: params["action"],
        data: params["data"]
      }
      
      # TODO: Implement actual CRM update via HubSpot service
      # Hubspot.update_contact(user, crm_data)
      
      Logger.info("CRM would be updated: #{inspect(crm_data)}")
      {:ok, %{action: "crm_updated", contact: params["contact_email"], crm_action: params["action"]}}
    else
      error -> error
    end
  end

  # Create a new task
  defp execute_create_task(params, user_id) do
    task_attrs = %{
      task_instruction: params["task_instruction"],
      current_stage_summary: "Task has been created and is ready for AI analysis",
      next_stage_instruction: "Analyze the task instruction and determine what tools and actions are needed to complete it",
      is_done: false,
      context: params["context"] || %{},
      user_id: user_id
    }
    
    case TaskRunner.create_task(task_attrs) do
      {:ok, task} ->
        # Create initial task stage
        stage_attrs = %{
          task_id: task.id,
          stage_name: "created",
          stage_type: "system",
          tool_name: "create_task",
          tool_params: params,
          tool_result: %{task_id: task.id},
          ai_reasoning: "Task created from AI analysis",
          status: "completed",
          started_at: DateTime.utc_now(),
          completed_at: DateTime.utc_now()
        }
        
        TaskRunner.create_task_stage(stage_attrs)
        {:ok, %{action: "task_created", task_id: task.id, instruction: params["task_instruction"]}}
      
      {:error, changeset} ->
        {:error, "Failed to create task: #{inspect(changeset.errors)}"}
    end
  end

  # Update task stage
  defp execute_update_task_stage(params, user_id) do
    task_id = params["task_id"]
    new_stage = params["new_stage"]
    stage_result = params["stage_result"] || %{}
    
    case TaskRunner.get_task(task_id) do
      {:ok, %TaskRunner.Task{user_id: ^user_id} = task} ->
        # Create new task stage record
        stage_attrs = %{
          task_id: task_id,
          stage_name: new_stage,
          stage_type: "ai_transition",
          tool_name: "update_task_stage",
          tool_params: params,
          tool_result: stage_result,
          ai_reasoning: "Stage updated via AI decision",
          status: "completed",
          started_at: DateTime.utc_now(),
          completed_at: DateTime.utc_now()
        }
        
        # Generate natural language stage summary and instruction
        stage_summary = case new_stage do
          "analyzing" -> "Task is being analyzed to determine required actions"
          "executing" -> "Task actions are being executed"
          "waiting_for_response" -> "Task is waiting for external response"
          "completed" -> "Task has been completed successfully"
          _ -> "Task is in progress: #{new_stage}"
        end
        
        next_instruction = case new_stage do
          "analyzing" -> "Determine what tools and actions are needed to complete the task"
          "executing" -> "Execute the required actions and tools to complete the task"
          "waiting_for_response" -> "Wait for the required response and process it when received"
          "completed" -> "No further action needed - task is done"
          _ -> "Continue with the next appropriate action based on current context"
        end
        
        with {:ok, _stage} <- TaskRunner.create_task_stage(stage_attrs),
             {:ok, _updated_task} <- TaskRunner.update_task(task, %{
               current_stage_summary: stage_summary,
               next_stage_instruction: next_instruction,
               context: Map.merge(task.context, stage_result)
             }) do
          {:ok, %{action: "task_stage_updated", task_id: task_id, new_stage: new_stage}}
        else
          {:error, changeset} ->
            {:error, "Failed to update task stage: #{inspect(changeset.errors)}"}
        end
      
      {:error, :not_found} ->
        {:error, "Task #{task_id} not found"}
      
      {:ok, _} ->
        {:error, "Task #{task_id} does not belong to user"}
    end
  end

  # Set task to wait for response (event-driven, no timeout)
  defp execute_wait_for_response(params, user_id) do
    task_id = params["task_id"]
    wait_type = params["wait_type"]
    context_update = params["context_update"] || %{}
    
    case TaskRunner.get_task(task_id) do
      {:ok, %TaskRunner.Task{user_id: ^user_id} = task} ->
        # Update task context with waiting information
        wait_context = Map.merge(context_update, %{
          "waiting_for" => wait_type,
          "wait_started_at" => DateTime.utc_now()
        })
        
        # Prepare task update attributes with natural language
        stage_summary = "Waiting for #{wait_type} response from #{params["sender_email"] || "recipient"}"
        next_instruction = case wait_type do
          "email" -> "Process the email reply when received and extract relevant information"
          _ -> "Process the response when received and determine next actions"
        end
        
        task_update_attrs = %{
          current_stage_summary: stage_summary,
          next_stage_instruction: next_instruction,
          context: Map.merge(task.context, wait_context)
        }
        
        # Email-specific context is now stored in the context map
        task_update_attrs = if wait_type == "email" do
          email_context = %{
            "thread_id" => params["thread_id"],
            "waiting_for_sender" => params["sender_email"],
            "expected_response_type" => params["response_type"] || "email_reply"
          }
          Map.update(task_update_attrs, :context, email_context, &Map.merge(&1, email_context))
        else
          task_update_attrs
        end
        
        # Create waiting stage
        stage_attrs = %{
          task_id: task_id,
          stage_name: "waiting_#{wait_type}",
          stage_type: "wait",
          tool_name: "wait_for_response",
          tool_params: params,
          tool_result: %{wait_type: wait_type},
          ai_reasoning: "Task set to wait for #{wait_type}",
          status: "waiting",
          started_at: DateTime.utc_now()
        }
        
        with {:ok, _stage} <- TaskRunner.create_task_stage(stage_attrs),
             {:ok, _updated_task} <- TaskRunner.update_task(task, task_update_attrs) do
          
          {:ok, %{action: "task_waiting", task_id: task_id, wait_type: wait_type}}
        else
          {:error, changeset} ->
            {:error, "Failed to set task waiting: #{inspect(changeset.errors)}"}
        end
      
      {:error, :not_found} ->
        {:error, "Task #{task_id} not found"}
      
      {:ok, _} ->
        {:error, "Task #{task_id} does not belong to user"}
    end
  end

  # Helper functions
  
  defp get_user(user_id) do
    case Accounts.get_user!(user_id) do
      nil -> {:error, "User not found"}
      user -> {:ok, user}
    end
  rescue
    _ -> {:error, "User not found"}
  end

  defp validate_email_params(params) do
    required_fields = ["to", "subject", "body"]
    missing_fields = Enum.filter(required_fields, fn field -> is_nil(params[field]) or params[field] == "" end)
    
    if Enum.empty?(missing_fields) do
      {:ok, params}
    else
      {:error, "Missing required email fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_meeting_params(params) do
    required_fields = ["title", "attendees", "start_time", "end_time"]
    missing_fields = Enum.filter(required_fields, fn field -> is_nil(params[field]) or params[field] == "" end)
    
    if Enum.empty?(missing_fields) do
      {:ok, params}
    else
      {:error, "Missing required meeting fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_crm_params(params) do
    required_fields = ["contact_email", "action", "data"]
    missing_fields = Enum.filter(required_fields, fn field -> is_nil(params[field]) or params[field] == "" end)
    
    if Enum.empty?(missing_fields) do
      {:ok, params}
    else
      {:error, "Missing required CRM fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  # Create assistant message in chat
  defp execute_create_assistant_message(params, user_id) do
    with {:ok, _user} <- get_user(user_id),
         {:ok, _} <- validate_assistant_message_params(params) do
      
      session_id = params["session_id"] || params["thread_id"]
      content = params["content"] || params["message"]
      
      if session_id do
        Logger.info("[ToolExecutor] Creating assistant message for session #{session_id}: #{String.slice(content, 0, 100)}...")
        case Finpilot.ChatMessages.create_assistant_message(session_id, user_id, content) do
          {:ok, message} ->
            Logger.info("[ToolExecutor] Assistant message created successfully with ID #{message.id}")
            {:ok, %{action: "assistant_message_created", content: content, message_id: message.id, session_id: session_id}}
          {:error, changeset} ->
            Logger.error("[ToolExecutor] Failed to create assistant message: #{inspect(changeset.errors)}")
            {:error, "Failed to create assistant message: #{inspect(changeset.errors)}"}
        end
      else
        Logger.error("[ToolExecutor] No session_id provided for assistant message: #{content}")
        {:error, "session_id is required for assistant messages"}
      end
    else
      error -> error
    end
  end

  # Create system notification
  defp execute_create_system_notification(params, user_id) do
    with {:ok, _user} <- get_user(user_id),
         {:ok, _} <- validate_system_notification_params(params) do
      
      # TODO: Implement actual system notification creation
      # Notifications.create_notification(user_id, %{
      #   title: params["title"],
      #   message: params["message"],
      #   type: params["type"] || "info"
      # })
      
      Logger.info("System notification would be created: #{params["title"]} - #{params["message"]}")
      {:ok, %{action: "system_notification_created", title: params["title"]}}
    else
      error -> error
    end
  end

  defp validate_assistant_message_params(params) do
    required_fields = ["session_id", "content"]
    missing_fields = Enum.filter(required_fields, fn field -> is_nil(params[field]) or params[field] == "" end)
    
    if Enum.empty?(missing_fields) do
      {:ok, params}
    else
      {:error, "Missing required assistant message fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  defp validate_system_notification_params(params) do
    required_fields = ["title", "message"]
    missing_fields = Enum.filter(required_fields, fn field -> is_nil(params[field]) or params[field] == "" end)
    
    if Enum.empty?(missing_fields) do
      {:ok, params}
    else
      {:error, "Missing required system notification fields: #{Enum.join(missing_fields, ", ")}"}
    end
  end

  # Removed hardcoded determine_next_stage function - now using natural language approach


end