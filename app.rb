require 'omniauth'
require 'omniauth-twitter'
require 'twitter'
require 'sinatra'

use OmniAuth::Strategies::Twitter, ENV['CONSUMER_KEY'], ENV['CONSUMER_SECRET']

enable :sessions

class SessionUser
  attr_accessor :id, :oauth_token, :oauth_token_secret

  def self.create_from_auth!(session, auth)
    session[:id] = auth["uid"]
    session[:oauth_token] = auth.credentials.token
    session[:oauth_token_secret] = auth.credentials.secret
    self.new(session)
  end

  def initialize(session)
    @id = session[:id]
    @oauth_token = session[:oauth_token]
    @oauth_token_secret = session[:oauth_token_secret]
  end

  def logged_in?
    @id && @oauth_token && @oauth_token_secret
  end
end

helpers do
  def current_user
    @current_user ||= SessionUser.new(session)
  end
end

before do
  if current_user.logged_in?
    Twitter.configure do |config|
      config.consumer_key = ENV['CONSUMER_KEY']
      config.consumer_secret = ENV['CONSUMER_SECRET']
      config.oauth_token = current_user.oauth_token
      config.oauth_token_secret = current_user.oauth_token_secret
    end
  end
end

get '/' do
  if current_user.logged_in?
    erb :query
  else
    erb :welcome
  end
end

get '/comparison' do
  return redirect '/' unless current_user.logged_in?

  #find the common friends
  common_friend_ids = Twitter.friend_ids(params[:user_1]).to_a & Twitter.friend_ids(params[:user_2]).to_a

  #cram the two users being compared into the query group
  ids_to_search = Twitter.users([params[:user_1], params[:user_2]] + common_friend_ids)

  #search for the common friend details in 100-friend chunks
  @common_friends = ids_to_search.each_slice(Twitter::API::Users::MAX_USERS_PER_REQUEST).map do |group|
    Twitter.users(group)
  end.flatten.sort_by(&:handle)

  #yank the two users being compared out of the result set
  @common_friends.delete_if do |user|
    if params[:user_1].downcase == user.handle.downcase
      @user_1 = user
    elsif params[:user_2].downcase == user.handle.downcase
      @user_2 = user
    end
  end

  erb :comparison
end

get '/auth/:name/callback' do
  SessionUser.create_from_auth!(session, request.env["omniauth.auth"])
  redirect '/'
end

get '/sign_in/?' do
  redirect '/auth/twitter?x_auth_access_type=read'
end

get '/sign_out' do
  session.clear
  redirect '/'
end
