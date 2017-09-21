defmodule Example.Bootstrap do

  use Application
  require Logger

  def init do
    # do nothing
  end

  def start(_type, _args) do

    Logger.info "start application"

    import Supervisor.Spec, warn: false

    opts = [strategy: :one_for_one,
            name:     Example.Supervisor]

    Riverside.Spec.child_spec([path: "/", port: 3000, module: Example.Session])
    |> Supervisor.start_link(opts)
  end

end
