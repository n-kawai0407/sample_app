#!/usr/bin/env ruby
# frozen_string_literal: true

# 記事の正本（aws-cert-materials/articles/*.md）から、各プラットフォーム向けの
# 公開用ファイルを生成するビルドスクリプト。
#
#   生成先:
#     articles/aws-<name>.md   … Zenn（リポジトリ連携でそのまま公開）
#     public/aws-<name>.md     … Qiita（Qiita CLI が読む public/。Rails の静的ファイルとは別名で共存）
#     note/aws-<name>.md       … note（frontmatter を除いた貼り付け用テキスト）
#
#   使い方:  ruby scripts/build_publish_articles.rb
#
# 正本だけを編集し、本スクリプトを再実行すれば 3 形式が一括で更新されます。
# 生成物は安全側（未公開）に倒しています。一斉公開を避けるため:
#   Zenn  … published: false（下書き）
#   Qiita … ignorePublish: true（CLI が公開対象から除外）
# 公開したい記事だけ、各ファイルのフラグを公開側に変更してください。

require "yaml"
require "fileutils"

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

ROOT        = File.expand_path("..", __dir__)
SOURCE_DIR  = File.join(ROOT, "aws-cert-materials", "articles")
ZENN_DIR    = File.join(ROOT, "articles")
QIITA_DIR   = File.join(ROOT, "public")
NOTE_DIR    = File.join(ROOT, "note")
SLUG_PREFIX = "aws-"

# 公開時に取り除く「編集メモ／制作メモ」見出し
CUT_HEADING = /\A##\s*(編集メモ|制作メモ)/

def parse(path)
  raw = File.read(path, encoding: "UTF-8")
  unless raw.start_with?("---\n")
    abort "frontmatter が見つかりません: #{path}"
  end
  _, fm, body = raw.split(/^---\s*$\n/, 3)
  [YAML.safe_load(fm), body]
end

# 先頭の編集用引用（> ネタ#...）と、末尾の編集メモ以降を取り除く
def clean_body(body)
  lines = body.lines

  # 先頭の空行を飛ばす
  lines.shift while lines.first && lines.first.strip.empty?
  # 先頭が引用ブロックなら、その塊を丸ごと除去
  if lines.first&.start_with?(">")
    lines.shift while lines.first&.start_with?(">")
    lines.shift while lines.first && lines.first.strip.empty?
  end

  # 末尾の編集メモ以降を除去（直前の区切り線 --- も落とす）
  if (idx = lines.index { |l| l.match?(CUT_HEADING) })
    idx -= 1 while idx.positive? && lines[idx - 1].strip.empty?
    idx -= 1 if idx.positive? && lines[idx - 1].strip == "---"
    lines = lines[0...idx]
  end

  lines.join.strip + "\n"
end

def slug_for(name)
  s = "#{SLUG_PREFIX}#{name}"
  unless s.match?(/\A[0-9a-z_-]{12,50}\z/)
    abort "Zenn のスラッグ規則(12-50字, a-z0-9-_)に違反: #{s}"
  end
  s
end

def write(path, content)
  File.write(path, content)
  puts "  + #{path.sub("#{ROOT}/", "")}"
end

def build_zenn(meta, body, slug)
  topics = Array(meta["topics"]).map { |t| %("#{t}") }.join(", ")
  <<~FM + body
    ---
    title: "#{meta["title"]}"
    emoji: "#{meta["emoji"] || "📝"}"
    type: "#{meta["type"] || "tech"}"
    topics: [#{topics}]
    published: false
    ---

  FM
end

def build_qiita(meta, body)
  tags = Array(meta["topics"]).first(5).map { |t| "  - #{t}" }.join("\n")
  <<~FM + body
    ---
    title: "#{meta["title"]}"
    tags:
    #{tags}
    private: false
    updated_at: ''
    id: null
    organization_url_name: null
    slide: false
    ignorePublish: true
    ---

  FM
end

def build_note(meta, body)
  "# #{meta["title"]}\n\n#{body}"
end

[ZENN_DIR, QIITA_DIR, NOTE_DIR].each { |d| FileUtils.mkdir_p(d) }

sources = Dir.glob(File.join(SOURCE_DIR, "*.md")).sort
abort "正本が見つかりません: #{SOURCE_DIR}" if sources.empty?

puts "#{sources.size} 件の正本を変換します..."
sources.each do |src|
  name = File.basename(src, ".md")
  slug = slug_for(name)
  meta, raw_body = parse(src)
  body = clean_body(raw_body)

  write(File.join(ZENN_DIR,  "#{slug}.md"), build_zenn(meta, body, slug))
  write(File.join(QIITA_DIR, "#{slug}.md"), build_qiita(meta, body))
  write(File.join(NOTE_DIR,  "#{slug}.md"), build_note(meta, body))
end
puts "完了。Zenn=#{ZENN_DIR.sub("#{ROOT}/", "")} / Qiita=public/ / note=note/ に出力しました。"
