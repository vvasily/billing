#!/usr/bin/perl -w

use FindBin qw($Bin);

#-------------------------------------------------------------------------------
# name:        appendStringToFile
# arguments:   $1 - Text string to place into the file
#              $2 - File name to write to
# returns:     none
# description: Creates the text file with specified name and writes the
#              specified text string appending return. If file exist then it is
#              appended.
#-------------------------------------------------------------------------------
sub appendStringToFile($$){
     my($text, $fileName) = @_;
     $text =~ /^(.*)$/ && ($text = $1);
     my($seconds, $minutes, $hours, $day_of_month, $month, $year) = (localtime)[0,1,2,3,4,5];
     my $curtime = sprintf("%02d:%02d:%02d %02d/%02d/%04d", $hours,$minutes,$seconds,$day_of_month,$month+1, $year+1900);
     
     $fileSymb = '>>';
     if(-e $fileName){
         ($size) = (stat($fileName))[7];
         $fileSymb = '>' if($size > 10000000);
     }

     open (FILE, $fileSymb, $fileName) or die "Can not open file $fileName";
     printf FILE "$curtime $text\n";
     close FILE or die "Can not close file $fileName";
}

$Bin =~ /^(.*)$/ && ($Bin = $1);
chdir $Bin;

%VAR_CFG = ();
$cfgFile = "./banconfig.cfg";
open(FILE,'<',"$cfgFile") || die "Cannot open cfg file";
while(<FILE>) 
{
    if(m/\b(.*)=(.*)\b/)
    {
        $VAR_CFG{$1} = $2;
    }
}
close(FILE);

$ENV{PATH} = "/bin:/usr/bin:";

$BAN_LIST_FILE = "ban_user.list";
$BAN_LIST_TMP = "ban_user.list.tmp";
$BANLOG = $VAR_CFG{'ban_log'};
$IPTABLES = $VAR_CFG{'iptables'};
$SCRIPT = "$0";
$APACHE_PORT = $VAR_CFG{'apache_port'};
$APACHE_HOST = $VAR_CFG{'apache_host'};

$IPTABLES =~ /^(.*)$/ && ($IPTABLES = $1);
$SCRIPT =~ /^(.*)$/ && ($SCRIPT = $1);
$APACHE_PORT =~ /^(.*)$/ && ($APACHE_PORT = $1);
$APACHE_HOST =~ /^(.*)$/ && ($APACHE_HOST = $1);

appendStringToFile("=============script started=============", $BANLOG);
appendStringToFile("$SCRIPT @ARGV", $BANLOG);

sub usage(){
   print "Usage: $SCRIPT add <list banned IPs> | $SCRIPT unban <list unbanned IPs>\n";
   exit 1;
}

sub add_iptables_ip($){
    my($list_ip) = @_;
    @ip_list = @$list_ip;

   foreach $node (@ip_list){
            
    open (IPTABLESOUT,"$IPTABLES -L -n|") or die "Could not execute 'iptables -L -n' command";
    chomp(@rslt = <IPTABLESOUT>) if(defined fileno IPTABLESOUT);   
    close(IPTABLESOUT) or die "Could not close iptables descriptor";
        
    if(!grep(/^REJECT(\s+)tcp(\s+)--(\s+)$node(\s+)/,@rslt)){
        $node =~ /^(.*)$/ && ($node = $1);
        @res = (system("$IPTABLES -I FORWARD 2 -p tcp -s $node -j REJECT --reject-with tcp-reset"),
		    system("$IPTABLES -t nat -I PREROUTING 2 -p tcp -s $node --dport 80 -j DNAT --to-destination $APACHE_HOST:$APACHE_PORT"));
        if(!grep(!/^0$/,@res)){
            appendStringToFile("User $node banned", $BANLOG);
        }
        else{
            appendStringToFile("Error occured for $node at ban!", $BANLOG);
        }
    }
    else{
        appendStringToFile("User $node is already in iptables", $BANLOG);
    }
   }
   return 0;
}

usage() if(($#ARGV + 1) == 0);

@cmdlineParameters = @ARGV;

if($cmdlineParameters[0] eq 'unban'){
    shift @cmdlineParameters;
    usage() if(($#cmdlineParameters + 1) == 0);
    appendStringToFile("Unbanned users...", $BANLOG);
    foreach $node (@cmdlineParameters){
        $node =~ /^(.*)$/ && ($node = $1);
        @res = (system("$IPTABLES -D FORWARD -p tcp -s $node -j REJECT --reject-with tcp-reset"),
            system("$IPTABLES -t nat -D PREROUTING -p tcp -s $node --dport 80 -j DNAT --to-destination $APACHE_HOST:$APACHE_PORT"));
        if(!grep(!/^0$/,@res)){
            if( -f $BAN_LIST_FILE){
            
                open (BANFILE, $BAN_LIST_FILE) or die "Could not open $BAN_LIST_FILE file";    
                open (BANFILETMP, ">$BAN_LIST_TMP") or die "Could not open $BAN_LIST_TMP file";
                while (<BANFILE>){
                    if (/^$node$/){
                        appendStringToFile("User $node removed from ban list", $BANLOG);
                        next; 
                    }
                    print BANFILETMP;
                }
                close(BANFILE) or die "Could not close $BAN_LIST_FILE file";
                close(BANFILETMP) or die "Could not close $BAN_LIST_TMP file";
                rename $BAN_LIST_TMP, $BAN_LIST_FILE;
            }
            else{
                appendStringToFile("$BAN_LIST_FILE file doesn't exist!", $BANLOG);
            }
            appendStringToFile("User $node unbanned", $BANLOG);
        }
        else{
            appendStringToFile("User $node did NOT unban!", $BANLOG);
        }
    }
    exit 0;
}
elsif($cmdlineParameters[0] eq 'ban'){
    shift @cmdlineParameters;
        
    if(($#cmdlineParameters + 1)>0){
        add_iptables_ip(\@cmdlineParameters);
    }
    else{
        @ban_list = ();
        if( -f $BAN_LIST_FILE){
            appendStringToFile("Reading $BAN_LIST_FILE...", $BANLOG);
            open (BANFILE, $BAN_LIST_FILE) or die "Could not open $BAN_LIST_FILE file";
            while (<BANFILE>){
                chomp($_);
                next if(!length($_));
                push(@ban_list,$_);
            }
            close(BANFILE) or die "Could not close $BAN_LIST_FILE file";
            add_iptables_ip(\@ban_list);        
        }
        else{
            appendStringToFile("$BAN_LIST_FILE file doesn't exist!", $BANLOG);
            exit 1;
        }
    }
}
elsif($cmdlineParameters[0] eq 'add'){
    shift @cmdlineParameters;
    usage() if(($#cmdlineParameters + 1) == 0);
        
    %hash = map { $_ => 1} @cmdlineParameters; 
    @cmdlineParameters = keys %hash; 

    @new_list = @cmdlineParameters;
    if( -f $BAN_LIST_FILE){
        my $index = 0;
        open (BANFILE,$BAN_LIST_FILE) or die "Could not open $BAN_LIST_FILE file";
        while(<BANFILE>){
            $index = 0;
            foreach $node (@cmdlineParameters){
                if(/^$node$/){
                    appendStringToFile("$node is already in ban list... Ignore it!", $BANLOG); 
                    splice(@new_list,$index,1);
                    --$index;
                }
                ++$index;
            }
            @cmdlineParameters = @new_list;
        }
        close(BANFILE);

        open (BANFILE, ">>$BAN_LIST_FILE") or die "Could not open $BAN_LIST_FILE file";
        foreach(@new_list){
            print BANFILE "$_\n";
        }
        close(BANFILE);
        system("$SCRIPT ban @new_list") if(($#new_list + 1)>0);
        exit 0;
    }
    else{
        appendStringToFile("$BAN_LIST_FILE file doesn't exist!", $BANLOG); 
        exit 1;
    }
}
else{
    usage();
}
exit 0;
