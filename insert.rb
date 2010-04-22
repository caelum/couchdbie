require 'net/http'
require 'simple_couch'
require 'json'

# def node(body, *links)
#   h = {"type" => "post", "body" => body}
#   h["links"] = links unless links.empty?
#   h.to_json
# end
# 
# def link(relation, id)
#   {"rel" => relation, "href" => ""}
# end

def node(body, options = {})
    h = {"type" => "post", "body" => body}
    options.each do |key, value|
      h[key] = options[key]
    end
    puts "i will send #{h.to_json}"
    h.to_json
end

server = Couch::Server.new("localhost", "5984")
server.delete("/foo")
server.put("/foo/", "")

doc = node("Rest is about an uniform interface!")
res = server.put("/foo/first", doc)
rev = JSON.parse(res.body)["rev"]
doc = node("Rest is about an uniform interface... updated", :_rev => rev)
server.put("/foo/first", doc)

doc = node("Rest is about linking data", :depends => "first")
server.put("/foo/second", doc)

doc = node("Rest is about linking data, again", :depends => "second")
server.put("/foo/third", doc)

# doc = "{\"type\":\"link\", \"from\":\"first\", \"to\":\"second\"}"
# server.put("/foo/link_1", doc)
# 
# doc = "{\"type\":\"link\", \"from\":\"first\", \"to\":\"third\"}"
# server.put("/foo/link_2", doc)
# 
# all_links = '{
#   "_id": "_design/application",
#   "views": {
#     "docs": {
#       "map": "function(doc) {
#         if (doc.type == \"link\") {
#           emit(doc.from, doc);
#         } else {
#           emit(\"123\", doc.id);
#         }
#       }",
#     }
#   }
# }'
# "reduce": "function(keys, values) { ... }"

# server.put("/foo/_design/application", all_links)