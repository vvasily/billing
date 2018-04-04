#!/usr/bin/perl -w
use DBI;

%VAR_CFG = ();
$cfgFile = "/etc/billing/billing.cfg";
open(FILE,'<',"$cfgFile") || die "Cannot open cfg file";
while(<FILE>) 
{
    if(m/\b(.*)=(.*)\b/)
    {
        $VAR_CFG{$1} = $2;
    }
}
close(FILE);

sub writeToLog($){
    my $msg_log = $_[0];
    my $log_file = $VAR_CFG{error_log};
    
    ($seconds, $minutes, $hours, $day_of_month, $month, $year) = (localtime)[0,1,2,3,4,5];
    $curtime = sprintf("%02d:%02d:%02d %02d/%02d/%04d", $hours,$minutes,$seconds,$day_of_month,$month+1, $year+1900);
    
    $fileSymb = '>>';
    if(-e $log_file){
        ($size) = (stat($log_file))[7];
        if($size > 10000000){
           $fileSymb = '>';
        }
        else{
           $fileSymb = '>>';
        }
    }

    open(FILELOG,$fileSymb,"$log_file") || die "Cannot open log file $log_file";
    print FILELOG "$curtime $msg_log\n";
    close(FILELOG);
}

$ban_script = $VAR_CFG{'ban_script'};
$balance_status = 0;

($abon_id, $pay_type) = @ARGV;

eval {
    $dbh = DBI->connect("dbi:mysql:database=billing;host=$VAR_CFG{db_url};mysql_multi_statements=1",$VAR_CFG{db_usr},$VAR_CFG{db_passwd},{mysql_multi_statements => 1,AutoCommit => 0,RaiseError => 1});
    $dbh->{mysql_server_prepare}=0;
        
    $dbh->do("SET NAMES 'utf8'");
    
    if($pay_type eq "internet"){
       $sql_command = "SELECT ModifyBalance('$abon_id');";
    }
    elsif($pay_type eq "catv"){
       $sql_command = "SELECT catv_ModifyBalance('$abon_id');";
    }
    else{
       writeToLog("$0 failed!");
       exit 1;
    }
        
    $sth = $dbh->prepare($sql_command);
    $sth->execute();
    while ( ( $balance_status ) = $sth->fetchrow_array ) {
        last;
    }
    $sth->finish;
    $dbh->commit();
    
    if($balance_status == 1 && $pay_type eq "internet"){
        #Unban client
        $abon_ip_ret = $router_ip = "";
        $sth = $dbh->prepare("SELECT router_ip, abon_ip FROM internet_abon, router_ip_list WHERE abon_sity=router_sity_id AND abon_personal_account='$abon_id'");
        $sth->execute();
        while ( ($router_ip, $abon_ip_ret ) = $sth->fetchrow_array ) {
           last;
        }
        $sth->finish;
        
        $res = system("$ban_script $router_ip unban $abon_ip_ret");
        writeToLog("Ban script on $router_ip has failed for $abon_ip_ret!") if($res != 0);
    }
};
if ($@){
    writeToLog("The error of DB happens: $@");
    ### Undo any database changes made before the error occurred
    $dbh->rollback() if defined($dbh);
    exit 1;
}
$dbh->disconnect() if defined($dbh);
exit 0;
                