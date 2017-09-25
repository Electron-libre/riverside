defmodule Riverside.TestClient do

  require Logger
  use GenServer

  defstruct sock: nil,
            codec: nil

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def send(pid, msg) do
    GenServer.cast(pid, {:send, msg})
  end

  def wait_to_test(pid, functions, timeout) do
    GenServer.call(pid, {:wait_messages, functions, timeout})
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def new(sock, codec) do
    %__MODULE__{sock: sock, codec: codec}
  end

  defp connect(host, port, path, headers \\ []) do
    Socket.Web.connect(host, port, path: path, headers: headers)
  end

  def init(opts) do

    host    = Keyword.get(opts, :host, "localhost")
    port    = Keyword.get(opts, :port, 8000)
    path    = Keyword.get(opts, :path, "/")
    headers = Keyword.get(opts, :headers, [])
    codec   = Keyword.get(opts, :codec, Riverside.Codec.JSON)

    case connect(host, port, path, headers) do

      {:ok, sock} ->
        start_receiver(sock)
        {:ok, new(sock, codec)}

      {:error, reason} ->
        {:stop, :disconnected}

    end

  end

  defp start_receiver(sock) do
    spawn_link fn -> receiver_loop(self(), sock) end
  end

  defp receiver_loop(parent, sock) do
    case receive_message(sock) do
      {:ok, type, data} ->
        send parent, {:data, type, data}
        receiver_loop(parent, sock)
      {:error, :unsupported_frame} ->
        receiver_loop(parent, sock)
    end
  end

  defp receive_message(sock) do
    case Socket.Web.recv!(sock) do
      {type, data} when type in [:text, :binary] ->
        {:ok, type, data}
      _other ->
        {:error, :unsupported_frame}
    end
  end

  defp decode_message(codec, type, packet) do
    if codec.frame_type === type do
      case codec.decode(packet) do

        {:ok, value} -> {:ok, value}

        {:error, reason} ->
          Logger.warn "TestClient - failed to decode received message: #{reason}"
          {:error, :bad_format}

      end
    else
      {:error, :unsupported_frame}
    end
  end

  defp wait_to_receive(timer, [], state) do
    :erlang.cancel_timer(timer)
    {:reply, :ok, state}
  end

  defp wait_to_receive(timer, [test|rest_tests], state) do
    receive do
      {:received, msg} ->
        case test.(msg) do
          :ok ->
            wait_to_receive(timer, rest_tests, state)
          :error ->
            {:reply, {:error, :failed}, state}
        end
      {:timeout, ^timer, :timeout} ->
        {:reply, {:error, :timeout}, state}
    end
  end

  def handle_call({:wait_to_receive, tests, timeout}, _from, state) do
    timer = :erlang.start_timer(timeout, self(), :timeout)
    wait_to_receive(timer, tests, state)
  end

  def handle_info({:data, type, data}, state) do
    case decode_message(state.codec, type, data) do
      {:ok, value}     -> {:noreply, state}
      {:error, reason} -> {:noreply, state}
    end
  end

  def handle_call(:stop, _from, state) do
    Socket.Web.close(state.sock)
    {:stop, :normal, :ok, state}
  end

  def handle_cast({:send, packet}, %{codec: codec}=state) do
    case codec.encode(packet) do

      {:ok, value} ->
        Socket.Web.send!(state.sock, {codec.frame_type, packet})
        {:noreply, state}

      {:error, reason} ->
        Logger.warn "TestClient - failed to format message: #{reason}"
        {:noreply, state}
    end
  end

  def terminate(_reason, _state) do
    :ok
  end

end
