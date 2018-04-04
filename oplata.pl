#!/usr/bin/perl -w

#apt-get install libclass-dbi-mysql-perl libxml-simple-perl

use warnings;
use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use DBI;
use utf8;
use XML::Simple qw(:strict);
use XML::Writer;
use Data::Dumper;

#Declare error codes
use constant {
        CODE_INTERN_ERR      => -3,
        CODE_TYPE_ERR        => -2,
        CODE_PARAM_ERR       => -1,
        CODE_SUCCESS         => 0,
        CODE_ACTION_ERR      => 1,
        CODE_CLIENT_ERR      => 2,
        CODE_PAY_ERR         => 3,
        CODE_NUM_PAY_ERR     => 4,
        CODE_DATE_ERR        => 5,
        CODE_CHK_PAY_ERR     => 6,
        CODE_ST_PAY_ERR      => 8,
        CODE_OTHER_ERR       => 11,
        CODE_CLIENT_CHK_ERR  => 746
    };

#Redirect to NULL
$outNull = '1>/dev/null 2>&1';

sub error_code($$){
   my ($err_code, $err_msg)=@_;
   my $hashref = {
          response => {
          code     => [ "$err_code" ],
          message  => [ "$err_msg" ],
      },
   };

   print $xs->XMLout($hashref);
   exit(1);
}

%VAR_CFG = ();
$cfgFile = "/etc/billing/billing.cfg";
open(FILE,'<',"$cfgFile") || die "Cannot open cfg file";
while(<FILE>) 
{
    if(m/\b(.*)=(.*)\b/)
    {
        $VAR_CFG{$1}=$2;
    }
}
close(FILE);

#Script for payment
$client_script = $VAR_CFG{'client_script'};

%check_type = (0 => 'internet',
               1 => 'catv'); 

$xs = XML::Simple->new(
                      RootName   => undef,
                      KeyAttr    => [],
                      XMLDecl    => "<?xml version='1.0' encoding='windows-1251' ?>",
      );

print "Content-type:text/xml\n\n"; 

eval {
   $dbh = DBI->connect("dbi:mysql:database=billing;
                        host=$VAR_CFG{db_url};
                        mysql_multi_statements=1",
                        $VAR_CFG{db_usr},
                        $VAR_CFG{db_passwd},
                        {mysql_multi_statements => 1,AutoCommit => 0,RaiseError => 1,PrintError => 1});
   
   $dbh->{mysql_server_prepare} = 0;
   $dbh->do("SET NAMES 'cp1251'");

   my $t_action;   #check, payment, status
   my $t_number;   #sting len 30
   my $t_type = 0; # number 
   my $t_amount;   # number 10 
   my $t_receipt;  # 15 < len 
   my $t_date;     #YYYY-MM-DDThh:mm:ss 2007-09-20T12:10:06
   my $rc;         #result code
   my $xmlout = "";
   my $ref; 
   my $code; 
   my $message;

   #exit if parameter is incorrect
   error_code(CODE_PARAM_ERR, "incorrect parameter") if(!defined(param('action')));
   
   $t_action = param('action');

   if ($t_action eq "check"){
 
      error_code(CODE_PARAM_ERR, "incorrect parameter") if(!defined(param('number')) || !defined(param('type')));
      $t_number = substr(param('number'),0,30);
      $t_type = substr(param('type'),0,30);
      
      $abon_surname = $abon_name = $abon_patronymic = '';	  
      
      #By default client not found
      $code = CODE_CLIENT_CHK_ERR;
      $message = "client not found";
      $p032 = "";
      
      if($check_type{$t_type} eq "internet"){
         $sql_command = "SELECT abon_surname, abon_name, abon_patronymic FROM internet_abon WHERE abon_personal_account='$t_number' AND abon_sity!=3 AND abon_sity!=4 AND abon_sity!=5 AND abon_sity!=6";
      }
      elsif($check_type{$t_type} eq "catv"){
         $sql_command = "SELECT tv_abon_surname, tv_abon_name, tv_abon_patronymic FROM catv_abon WHERE tv_abon_personal_account='$t_number' AND tv_abon_sity!=3";
      }
      else{
         error_code(CODE_TYPE_ERR, "incorrect type parameter");
      }
      $sth = $dbh->prepare($sql_command);
      $sth->execute();
      while ( ( $abon_surname, $abon_name, $abon_patronymic ) = $sth->fetchrow_array ) {
         $code = CODE_SUCCESS;
         $message = "client has been found";
         if(defined($abon_surname) && length($abon_surname)){
             $p032 = $p032.$abon_surname; 
         }
         if(defined($abon_name) && length($abon_name)){
             $p032 = $p032." ".substr($abon_name, 0, 1).".";
         }
         if(defined($abon_patronymic) && length($abon_patronymic)){
             $p032 = $p032.substr($abon_patronymic, 0, 1).".";
         }
         last;
      }
      $sth->finish;
       my $hashref;
      if(length($p032)){
          $hashref = {
                      response => {
                      code     => [ "$code" ],
                      message  => [ "$message" ],
                      p032     => [ "$p032" ],
                     },
                    };
      }
      else{
          $hashref = {
                      response => {
                      code     => [ "$code" ],
                      message  => [ "$message" ],
                     },
                    };
      }

      print $xs->XMLout($hashref);
   }
   elsif ($t_action eq "payment")
   {
      error_code(CODE_PARAM_ERR, "incorrect parameter") if(!defined(param('receipt')) || 
                                                           !defined(param('number'))  ||
                                                           !defined(param('type'))    ||
                                                           !defined(param('amount'))  ||
                                                           !defined(param('date')));
      $t_receipt = substr(param('receipt'),0,30);
      $t_number = substr(param('number'),0,30);
      $t_type = substr(param('type'),0,30);
      $t_amount = substr(param('amount'),0,30);
      $t_date = substr(param('date'),0,30);

      #format for DB
      $t_date =~s/T/ /;
      
      #By default payment failed
      $code = CODE_NUM_PAY_ERR;
      $message = "payment failed";
      $authcode = -1;

      if($check_type{$t_type} eq "internet"){
         $sql_command = "CALL inetOplataPay('$t_number', '$t_date', $t_amount, '$t_receipt', \@auth_code);";
      }
      elsif($check_type{$t_type} eq "catv"){
         $sql_command = "CALL catvOplataPay('$t_number', '$t_date', $t_amount, '$t_receipt', \@auth_code);";
      }
      else{
         error_code(CODE_TYPE_ERR, "incorrect type parameter");
      }
      
      $dbh->do($sql_command);
      $authcode = $dbh->selectrow_array('SELECT @auth_code');
      
      if($authcode>0){
         $code = CODE_SUCCESS;
         $message = "payment successful";
        
         #Run script to update client status
         system("$client_script $t_number $check_type{$t_type} $outNull &");
      }
      
      #format date YYYY-MM-DDThh:mm:ss
      my($seconds, $minutes, $hours, $day_of_month, $month, $year) = (localtime)[0,1,2,3,4,5];
      $date = sprintf("%04d-%02d-%02dT%02d:%02d:%02d",$year+1900,$month+1,$day_of_month,$hours,$minutes,$seconds);
      
      my $hashref = {
          response => {
          code     => [ "$code" ],
          authcode => [ "$authcode" ],
          date     => [ "$date" ],
          message  => [ "$message" ],
          },
      };
      print $xs->XMLout($hashref);
   }
   elsif ($t_action eq "status")
   {
      error_code(CODE_PARAM_ERR, "incorrect parameter") if(!defined(param('receipt')));
      $t_receipt = substr(param('receipt'),0,30);
      
      #By default payment not found
      $code = CODE_CHK_PAY_ERR;
      $authcode =-1;
      $date = '';
      $message="payment not found";
      
      $sth = $dbh->prepare("(SELECT pay_id_operation, pay_date
                             FROM internet_pay_move
                             WHERE pay_oplata_id='$t_receipt')
                             UNION
                            (SELECT tv_pay_id_operation, tv_pay_date
                             FROM catv_pay_move
                             WHERE tv_pay_oplata_id='$t_receipt')
                             LIMIT 1;");
      $sth->execute();
      while ( ( $pay_id_operation, $pay_date ) = $sth->fetchrow_array ) {
         $code = CODE_SUCCESS;
         #format for DB
         $pay_date =~s/\s+/T/;
         $date = $pay_date;
         $authcode = $pay_id_operation;
         $message = "payment has been found";
         last;
      }
      $sth->finish;

      my $hashref = {
          response => {
              code     => [ "$code" ],
              authcode => [ "$authcode" ],
              date     => [ "$date" ],
              message  => [ "$message" ],
          },
      };
      print $xs->XMLout($hashref);
   }
   else {
      error_code(CODE_ACTION_ERR, "incorrect action parameter");
   }
};
if ($@){
    ### Undo any database changes made before the error occured
    $dbh->rollback() if defined($dbh);
    error_code(CODE_OTHER_ERR, "The error of DB happens");
}
$dbh->disconnect() if defined($dbh);
exit(0);
