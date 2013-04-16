require "sinatra/base"
require "rack-ssl-enforcer"

require "yajl/json_gem"
require "restclient"

require 'uri'


module Umpire
  ### Exception classes
  class MetricNotFound < Exception ; end
  class MetricServiceRequestFailed < Exception ; end
  class MetricNotComposite < RuntimeError ; end

  ### Graphite helper to fetch metric values
  module Graphite
    extend self

    def get_values_for_range(graphite_url, metric, range)
      begin
        json = RestClient.get(url(graphite_url, metric, range))
        data = JSON.parse(json)
        data.empty? ? raise(MetricNotFound) : data.first["datapoints"].map { |v, _| v }.compact
      rescue RestClient::RequestFailed
        raise MetricServiceRequestFailed
      end
    end

    def url(graphite_url, metric, range)
      URI.encode(URI.decode("#{graphite_url}/render/?target=#{metric}&format=json&from=-#{range}s"))
    end
  end

  ## Sinatra Web
  class Web < Sinatra::Base
    enable :dump_errors
    disable :show_exceptions
    use Rack::SslEnforcer if ENV['FORCE_HTTPS']

    before do
      content_type :json
    end

    helpers do
      def valid?(params)
        params["metric"] && (params["min"] || params["max"]) && params["range"]
      end

      def fetch_points(params)
        metric = params["metric"]
        range = (params["range"] && params["range"].to_i)

        return Graphite.get_values_for_range(ENV['GRAPHITE_URL'], metric, range)
      end
    end

    get "/check" do

      unless valid?(params)
        status 400
        next JSON.dump({"error" => "missing parameters"}) + "\n"
      end

      min = (params["min"] && params["min"].to_f)
      max = (params["max"] && params["max"].to_f)
      empty_ok = params["empty_ok"]

      begin
        points = fetch_points(params)
        if points.empty?
          status empty_ok ? 200 : 404
          JSON.dump({"error" => "no values for metric in range"}) + "\n"
        else
          value = (points.reduce { |a,b| a+b }) / points.size.to_f
          if ((min && (value < min)) || (max && (value > max)))
            status 500
          else
            status 200
          end
          JSON.dump({"value" => value}) + "\n"
        end
      rescue MetricNotComposite => e
        status 400
        JSON.dump("error" => e.message) + "\n"
      rescue MetricNotFound
        status 404
        JSON.dump({"error" => "metric not found"}) + "\n"
      rescue MetricServiceRequestFailed
        status 503
        JSON.dump({"error" => "connecting to backend metrics service failed with error 'request timed out'"}) + "\n"
      end
    end

    get "/health" do
      status 200
      JSON.dump({"health" => "ok"}) + "\n"
    end

    get "/*" do
      status 404
      JSON.dump({"error" => "not found"}) + "\n"
    end

    error do
      status 500
      JSON.dump({"error" => "internal server error"}) + "\n"
    end

  end
end
