require 'uri'

class ThumperSearchDelegate
    attr_accessor :parent, :search_query, :search_table_view, :search_progress, :search_count_label
    
    def initialize
        @search = []
    end
    
    def awakeFromNib
        search_table_view.doubleAction = 'double_click:'
        search_table_view.target = self
    end
    
    def double_click(sender)
        row = @search_table_view.selectedRow
        row = 0 if row.nil?
        @parent.add_to_current_playlist(@search[row])
    end
    
    def numberOfRowsInTableView(tableView)
        @search.count
    end
    
    def tableView(tableView, objectValueForTableColumn:column, row:row)
        #NSLog "Asked for Song Row:#{row}, Column:#{column.identifier}"
        if row < @search.length
            return @search[row].valueForKey(column.identifier.to_sym)
        end
        nil
    end
    
    def textInputOnEnterPressed(sender)
        reload_search
        NSLog "searching for by #{search_query.stringValue}"
        query = URI.escape(search_query.stringValue.downcase.strip)
        @search_progress.stopAnimation(nil)
        unless query.length < 3
            @search = []
            reload_search
            @search_progress.startAnimation(nil)
            parent.subsonic.search(query, self, :search_response)
        end
    end
    
    def add_selected(sender)
        rows = search_table_view.selectedRowIndexes
        if rows.count > 0
            rows.each do |row|
                song = @parent.search_results[row]
                @parent.add_to_current_playlist(song, false) 
            end
        else
            @search.each do |song|
                parent.add_to_current_playlist(song, false)
            end
        end
        parent.reload_current_playlist
        parent.play_song if parent.current_playlist.length == 1
    end
    
    def reload_search
        @search.count != 1 ? word = " Songs" : word = " Song"
        @search_count_label.stringValue = @search.count.to_s + word
        search_table_view.reloadData
    end
    
    def tableView(aView, writeRowsWithIndexes:rowIndexes, toPasteboard:pboard)
        songs_array = []
        rowIndexes.each do |row|
            songs_array << @search[row]
        end
        pboard.setString(songs_array.to_yaml, forType:"Songs")
        return true
    end
    
    def search_response(xml)
        NSLog "got a response"
        if xml.class == NSXMLDocument
            songs = xml.nodesForXPath("subsonic-response", error:nil).first.nodesForXPath('searchResult', error:nil).first.nodesForXPath('match', error:nil)
            attributeNames = ["id", "title", "artist", "coverArt", "parent", "isDir", "duration", "bitRate", "track", "year", "genre", "size", "suffix",
            "album", "path", "size"]
            if songs.length > 0
                @search = []
                songs.each do |xml_song|
                    song = {}
                    attributeNames.each do |name|
                        song[name.to_sym] = xml_song.attributeForName(name).stringValue unless xml_song.attributeForName(name).nil? 
                    end
                    song[:cover_art] = Dir.home + "/Library/Thumper/CoverArt/#{song[:coverArt]}.jpg"
                    song[:album_id] = song[:parent]
                    song[:bitrate] = song[:bitRate]
                    song[:duration] = @parent.format_time(song[:duration].to_i)
                    song[:cache_path] = Dir.home + '/Music/Thumper/' + song[:path]
                    @search << song if song[:isDir] == "false"
                end 
            end
            @parent.search_results = @search
            reload_search
            @search_progress.stopAnimation(nil)
            Dispatch::Queue.new('com.Thumper.db').async do
                @search.each do |s|
                    return if DB[:songs].filter(:id => s[:id]).all.first 
                    DB[:songs].insert(:id => s[:id], :title => s[:title], :artist => s[:artist], :duration => s[:duration], 
                                      :bitrate => s[:bitrate], :track => s[:track], :year => s[:year], :genre => s[:genre],
                                      :size => s[:size], :suffix => s[:suffix], :album => s[:album], :album_id => s[:album_id],
                                      :cover_art => s[:cover_art], :path => s[:path], :cache_path => s[:cache_path])
                    NSLog "Added songs: #{s[:title]}"
                end
            end
        else
            NSLog "#{xml}"
        end
    end
    
end