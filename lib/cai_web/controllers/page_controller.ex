defmodule CAIWeb.PageController do
  use CAIWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
