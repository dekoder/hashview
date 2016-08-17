require 'resque'
require 'dm-sqlite-adapter'
require 'data_mapper'
require './model/master.rb'

def update_db_status(id, status)
  jobtask = Jobtasks.first(:id => id)
  jobtask.status = status
  jobtask.save

  # if this is the last task for this current job, then set the job to be completed
  # find the job of the jobtask id:
  job = Jobs.first(:id => jobtask.job_id)
  # find all tasks for current job:
  jobtasks = Jobtasks.all(:job_id => job.id)
  # if no more jobs are set to queue, consider the job completed
  done = true
  jobtasks.each do |jt|
    if jt.status == 'Queued' || jt.status == 'Running'
      done = false
      break
    end
  end
  # toggle job status
  if done == true
    job.status = 0
    job.save
  end
end

module Jobq
  @queue = :hashcat

  def self.perform(id, cmd)

    jobtasks = Jobtasks.first(:id => id)

    puts "===== creating hashFile ======="
    targets = Targets.all(:jobid => jobtasks.job_id, :cracked => false)
    hashFile = "control/hashes/hashfile_" + jobtasks.job_id.to_s + "_" + jobtasks.task_id.to_s + ".txt"
    File.open(hashFile, 'w') do |f|
      targets.each do | entry |
        f.puts entry.originalhash
      end
      f.close
    end

    puts "===== HashFile Created ======"
    
    puts '===== starting job ======='
    update_db_status(id, 'Running')
    puts id
    puts cmd
    system(cmd)
    puts 'job completed'

    # this assumes a job completed successfully. we need to add check for failures or killed processes
    puts '==== Importing cracked hashes ====='
    jobtasks = Jobtasks.first(:id => id)
    crack_file = "control/outfiles/hc_cracked_" + jobtasks.job_id.to_s + "_" + jobtasks.task_id.to_s + ".txt"


    #adapter = DataMapper::repository(:default).adapter
    #adapter.select("PRAGMA synchronous = ON;")
    File.open(crack_file).each do |line|
      hash_pass = line.split(/:/)
      plaintext = hash_pass[1]
      plaintext = plaintext.chomp 
      #records = Targets.all(:originalhash => hash_pass[0], :cracked => false)
      #records.update(:plaintext => plaintext, :cracked => true)
      #records.update(:cracked => true)
      records = Targets.all(:cracked => false)
      records.each do | entry |
        if entry.originalhash == hash_pass[0]
          entry.cracked = true
          entry.plaintext = plaintext
        end
      end
      records.save
    end

    puts '==== import complete ===='

    update_db_status(id, 'Completed')
  end
end
