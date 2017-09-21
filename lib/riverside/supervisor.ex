defmodule Riverside.Supervisor do

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    children(opts) |> supervise(strategy: :one_for_one)
  end

  def children(opts) do

    router = Keyword.get(opts, :router, Riverside.Router)

    [Plug.Adapters.Cowboy.child_spec(:http, router, [],
      cowboy_opts(router, opts))]

  end

  defp cowboy_opts(router, opts) do

    module = Keyword.fetch!(opts, :module)
    port   = Keyword.fetch!(opts, :port)
    path   = Keyword.fetch!(opts, :path)

    cowboy_opts = [port: port, dispatch: dispatch_opts(module, router, path)]

    if Keyword.get(opts, :reuse_port, false) do
      cowboy_opts ++ [{:raw, 1, 15, <<1, 0, 0, 0>>}]
    else
      cowboy_opts
    end

  end

  defp dispatch_opts(module, router, path) do
    [
      {:_, [
        {path, Riverside.Connection, [session_module: module]},
        {:_, Plug.Adapters.Cowboy.Handler, {router, []}}
      ]}
    ]
  end

end
