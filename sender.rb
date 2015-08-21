require 'rest-client'
require 'json'
require 'date'
require 'csv'
require 'yaml'

CONFIG = YAML.load_file( File.dirname(__FILE__) + '/secrets/secrets.yml')
date = Date.today-2

file_date = date.strftime("%Y%m")
csv_file_name = "reviews_#{CONFIG["package_name"]}_#{file_date}.csv"

system "BOTO_PATH=#{File.dirname(__FILE__)}/secrets/.boto #{File.dirname(__FILE__)}/gsutil/gsutil cp -r gs://#{CONFIG["app_repo"]}/reviews/#{csv_file_name} ."


class Slack
  def self.notify(message)
    CONFIG["slack_urls"].each do |url|
      RestClient.post url, {
	payload:
	  { text: message }.to_json
	},
	content_type: :json,
	accept: :json
    end
  end

  def self.debug_notify(message)
	puts message.to_json
  end
end

class Review
  def self.collection
    @collection ||= []
  end

  def self.send_reviews_from_date(date)
    message = collection.select do |r|
      r.submitted_at > date && (r.title || r.text)
    end.sort_by do |r|
      r.submitted_at
    end.map do |r|
      r.build_message
    end.join("\n")


    if message != ""
      Slack.notify(message)
      #Slack.debug_notify(message)
    else
      print "No new reviews\n"
      Slack.notify("No new reviews")
      #Slack.debug_notify("No new reviews")
    end
  end

  attr_accessor :text, :title, :submitted_at, :original_subitted_at, :rate, :device, :url, :version, :edited

  def initialize data = {}
    @text = data[:text] ? data[:text].to_s.encode("utf-8") : nil
    @title = data[:title] ? "*#{data[:title].to_s.encode("utf-8")}*\n" : nil

    @submitted_at = DateTime.parse(data[:submitted_at].encode("utf-8"))
    @original_subitted_at = DateTime.parse(data[:original_subitted_at].encode("utf-8"))

    @rate = data[:rate].encode("utf-8").to_i
    @device = data[:device] ? data[:device].to_s.encode("utf-8") : nil
    @url = data[:url].to_s.encode("utf-8")
    @version = data[:version].to_s.encode("utf-8")
    @edited = data[:edited]
  end

  def notify_to_slack
    if text || title
      message = "*Rating: #{rate}* | version: #{version} | subdate: #{submitted_at}\n #{[title, text].join(" ")}\n <#{CONFIG['app_url']}| Go To App>"
      Slack.notify(message)
    end
  end

  def debug_notify
    if text || title
      message = "*Rating: #{rate}* | version: #{version} | subdate: #{submitted_at}\n #{[title, text].join(" ")}\n <#{CONFIG['app_url']}| Go To App>"
      puts message
    end
  end

  def build_message
    date = if edited
             "Date: #{original_subitted_at.strftime("%m.%d.%Y at %I:%M%p")}, edited at: #{submitted_at.strftime("%m.%d.%Y at %I:%M%p")}"
           else
             "Date: #{submitted_at.strftime("%m.%d.%Y at %I:%M%p")}"
           end

    stars = rate.times.map{"★"}.join + (5 - rate).times.map{"☆"}.join

    [
      "\n\n#{stars}",
      "<#{url} | #{title} >",
      "#{text}",
      "<#{CONFIG['app_url']}| Go To Play Store for #{CONFIG['app_name']}>"
      "Version: #{version} | #{date}",
    ].join("\n")
  end
end

CSV.foreach(csv_file_name, encoding: 'bom|utf-16le', headers: true) do |row|
  # If there is no reply - push this review
  if row[11].nil?
    app_version = nil
  	if row[1]
	  app_version = CONFIG['app_versions'][row[1].encode("UTF-8")]
	end
    Review.collection << Review.new({
      text: row[10],
      title: row[9],
      submitted_at: row[6],
      edited: (row[4] != row[6]),
      original_subitted_at: row[4],
      rate: row[8],
      device: row[3],
      url: row[14],
      version: app_version || row[1],
    })
  end
end

Review.send_reviews_from_date(date)
