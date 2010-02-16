class Youtube < PluginBase
	require "cgi"
	require "open-uri"
	require "nokogiri"

	#this will be called by the main app to check weather this plugin is responsible for the url passed
	def self.matches_provider?(url)
		url.include?("youtube.com")
	end
	
	def self.parse_playlist(url)
		#http://www.youtube.com/view_play_list?p=F96B063007B44E1E&search_query=welt+auf+schwäbisch
		#http://www.youtube.com/watch?v=9WEP5nCxkEY&videos=jKY836_WMhE&playnext_from=TL&playnext=1
		#http://www.youtube.com/watch?v=Tk78sr5JMIU&videos=jKY836_WMhE

		playlist_ID = url[/p=(\w{16})&?/,1]
		puts "[YOUTUBE] Playlist ID: #{playlist_ID}"
		url_array = Array.new
		video_info = Nokogiri::HTML(open("http://gdata.youtube.com/feeds/api/playlists/#{playlist_ID}?v=2"))
		video_info.search("//content").each do |video|
			url_array << video["url"] if video["url"].include?("http://www.youtube.com/v/") #filters out rtsp links
		end

		puts "[YOUTUBE] #{url_array.size} links found!"
		url_array
	end
	
	
	def self.download(url)
		if url.include?("view_play_list")
			puts "[YOUTUBE] playlist found! analyzing..."
			files = self.parse_playlist(url)
			puts "[YOUTUBE] Starting playlist download"
			files.each do |file|
				puts "[YOUTUBE] Downloading next movie on the playlist (#{file})"
				self.download_movie(file)
			end	
		else
			self.download_movie(url)
		end
	end
	
	def self.download_movie(url)
		#the youtube video ID looks like this: [...]v=abc5a5_afe5agae6g&[...], we only want the ID (the \w in the brackets)
		#addition: might also look like this /v/abc5-a5afe5agae6g
		# alternative:	video_id = url[/v[\/=]([\w-]*)&?/, 1]
		video_id = url[/v[\/=](.*)/,1]
		puts "[YOUTUBE] ID FOUND: " + video_id
		
		#let's get some infos about the video. data is urlencoded
		video_info = CGI::unescape(open("http://youtube.com/get_video_info?video_id=#{video_id}").read)

		#converting the huge infostring into a hash. simply by splitting it at the & and then splitting it into key and value arround the =
		#[...]blabla=blubb&narf=poit&marc=awesome[...]
		video_info_hash = Hash[*video_info.split("&").collect { |v| 
			[v.split("=")[0], v.split("=")[1]]
		}.flatten]
		
		if video_info_hash["status"] == "fail"
			puts "Error: embedding disabled, no video info found"
			return false
		end
		
		title = video_info_hash["title"]
		length_s = video_info_hash["length_seconds"]
		token = video_info_hash["token"]

		
		#Standard = 34 <- flv
		#Medium = 18 <- mp4
		#High = 35 <- flv
		#720p = 22 <- mp4
		#1080p = 37 <- mp4
		#mobile = 17 <- 3gp
		# --> 37 > 22 > 35 > 18 > 34 > 17
		formats = video_info_hash["fmt_map"].split(",").map{|item| item.split("/").first}
		
		format_ext = Hash.new
		format_ext["37"] = ["mp4", "MP4 Highest Quality 1920x1080"]
		format_ext["22"] = ["mp4", "MP4 1280x720"]
		format_ext["35"] = ["flv", "FLV 854x480"]
		format_ext["34"] = ["flv", "FLV 640x360"]
		format_ext["18"] = ["mp4", "MP4 480x270"]
		format_ext["17"] = ["3gp", "3gp"]
		format_ext["5"] = ["flv", "old default?"]
		
		puts "[YOUTUBE] Title: #{title}"
		puts "[YOUTUBE] Length: #{length_s} s"
		puts "[YOUTUBE] t-parameter: #{token}"
		#best quality seems always to be firsts
		puts "[YOUTUBE] formats available: #{formats} (downloading ##{formats.first} -> #{format_ext[formats.first].last})"


		download_url = "http://www.youtube.com/get_video?video_id=#{video_id}&t=#{token}%3D&fmt=#{formats.first}"
		file_name = title.delete("\"'").gsub(/[^0-9A-Za-z]/, '_') + "." + format_ext[formats.first].first
		puts "downloading to " + file_name
		save_file(download_url, file_name)
	end
end
