require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::YoutubeAgent do
  before(:each) do
    @valid_options = Agents::YoutubeAgent.new.default_options
    @checker = Agents::YoutubeAgent.new(:name => "YoutubeAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
