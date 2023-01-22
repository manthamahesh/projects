import tweepy
import pandas as pd
import json
from datetime import datetime
import s3fs

access_key = "access key goes here"
access_secret = "secret key goes here"
consumer_key = "consumer key goes here"
consumer_secret = "consumer secret key goes here"

auth = tweepy.OAuthHandler(access_key, access_secret)
auth.set_access_token(consumer_key, consumer_secret)

api = tweepy.API(auth)

tweets = api.user_timeline(screen_name = '@simonsinek', count = 200, include_rts = False, tweet_mode = 'extended')

print(tweets)

tweet_list= []
for tweet in tweets:
    text = tweet._json["full_text"]

    refined_tweet = {"user": tweet.user.screen_name,
                        'text' : text,
                        'favorite_count' : tweet.favorite_count,
                        'retweet_count' : tweet.retweet_count,
                        'created_at' : tweet.created_at}
    tweet_list.append(refined_tweet)

df = pd.DataFrame(tweet_list)
df.to_csv("Simon_Sinek_tweets_data.csv")
