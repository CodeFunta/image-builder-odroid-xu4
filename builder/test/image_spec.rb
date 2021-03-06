require_relative 'spec_helper'

describe "SD card image" do
  it "exists" do
    image_file = file(image_path)
    expect(image_file).to exist
  end

  context "Partition table" do
    let(:stdout) { run("list-filesystems").stdout }

    it "has one partition" do
      partitions = stdout.split(/\r?\n/)
      expect(partitions.size).to be 1
    end

    it "has a root-partition with a ext4 filesystem" do
      expect(stdout).to contain('sda1: ext4')
    end
  end

  context "Binary dpkg" do
    let(:stdout) { run_mounted("file-architecture /usr/bin/dpkg").stdout }

    it "is compiled for ARM architecture" do
      expect(stdout).to contain('arm')
    end
  end
end
