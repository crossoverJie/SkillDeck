# Homebrew Cask Formula Template for SkillDeck
#
# 这个文件是 Homebrew Cask 配方的模板，用于 `brew install --cask skilldeck`
#
# 使用方法：
#   1. 创建一个新仓库: github.com/crossoverJie/homebrew-skilldeck
#   2. 将此文件放在: Casks/skilldeck.rb
#   3. 每次发布新版本时，更新 version 和 sha256
#
# 用户安装命令：
#   brew tap crossoverJie/skilldeck
#   brew install --cask skilldeck
#
# 计算 sha256：
#   shasum -a 256 SkillDeck-vX.Y.Z-universal.zip

cask "skilldeck" do
  version "0.0.1"
  sha256 "6356ee6d06b82d3c35a372e76b0a875fe22c12a2ec64dc3be6f8c4c304f61314"

  url "https://github.com/crossoverJie/SkillDeck/releases/download/v#{version}/SkillDeck-v#{version}-universal.zip"
  name "SkillDeck"
  desc "Native macOS application for managing AI code agent skills"
  homepage "https://github.com/crossoverJie/SkillDeck"

  # 要求 macOS Sonoma 或更高版本
  depends_on macos: ">= :sonoma"

  # 告诉 Homebrew 将 .app 移动到 /Applications/
  app "SkillDeck.app"

  # zap 定义完全卸载时需要清理的文件
  # 只在 brew zap（非 brew uninstall）时执行
  zap trash: [
    "~/.agents/.skill-lock.json",
  ]
end
