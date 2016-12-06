# SCRIPT VERSION 1.0

# Require librairies!
use strict;
use warnings;
use Data::Dumper;
use DBI;

# Nimsoft
use lib "D:/apps/Nimsoft/perllib";
use lib "D:/apps/Nimsoft/Perl64/lib/Win32API";
use Nimbus::API;
use Nimbus::CFG;
use Nimbus::PDS;

# librairies
use perluim::main;
use perluim::log;


# ************************************************* #
# Console & Global vars
# ************************************************* #
my $Console = new perluim::log("archive_cleaner.log",5);
my $ScriptExecutionTime = time();
$Console->print("Execution start at ".localtime(),5);

sub breakApplication {
    $Console->print("Break Application (CTRL+C) !!!",0);
    $Console->close();
    exit(1);
}
$SIG{INT} = \&breakApplication;

# ************************************************* #
# Instanciating configuration file!
# ************************************************* #
my $CFG = Nimbus::CFG->new("archive_cleaner.cfg");
my $CFG_Login           = $CFG->{"setup"}->{"login"} || "administrator";
my $CFG_Password 	    = $CFG->{"setup"}->{"password"} || "nim76prox";
my $CFG_Audit           = $CFG->{"setup"}->{"audit"} || 0;
my $CFG_Domain 		    = $CFG->{"setup"}->{"domain"} || "NMS-PROD";
my $CFG_Ouput		    = $CFG->{"setup"}->{"output_directory"} || "output";
my $CFG_Cache		    = $CFG->{"setup"}->{"output_cache"} || 3;
my $CFG_Loglevel        = $CFG->{"setup"}->{"loglevel"} || 3;
my $CFG_OriginalHub     = $CFG->{"setup"}->{"original_hub"} || "GLNMS-PHUB";
my $CFG_UpdateRule      = $CFG->{"setup"}->{"update_rules"} || 0;
my $CFG_CheckCMDB       = $CFG->{"setup"}->{"checkcmdb"} || 0;

$Console->print("Print script configuration : ",5);
foreach($CFG->getKeys($CFG->{"setup"})) {
    $Console->print("Configuration : $_ => $CFG->{setup}->{$_}");
}

# ************************************************* #
# DBI
# ************************************************* #
my $DB;
if($CFG_CheckCMDB){
    my $DB_User         = $CFG->{"CMDB"}->{"sql_user"};
    my $DB_Password     = $CFG->{"CMDB"}->{"sql_password"};
    my $DB_SQLServer    = $CFG->{"CMDB"}->{"sql_host"};
    my $DB_Database     = $CFG->{"CMDB"}->{"sql_database"};

    $DB = DBI->connect("$DB_SQLServer;UID=$DB_User;PWD=$DB_Password",{
        RaiseError => 1,
        AutoCommit => 1
    });

    if(not defined($DB)) {
        $Console->print("Failed to contact database!");
        $Console->close();
        exit(1);
    }
    else {
        $Console->print("Contact database successfull! Connection info : $DB_Database");
        $DB->do("USE $DB_Database");
    }
}

# Set loglevel
$Console->setLevel($CFG_Loglevel);

nimLogin("$CFG_Login","$CFG_Password") if defined($CFG_Login) and defined($CFG_Password);

# ************************************************* #
# Instanciating framework !
# ************************************************* #
$| = 1;
$Console->print("Instanciating bnpp framework!",5);
my $SDK = new perluim::main($CFG_Domain);
$Console->print("Create $CFG_Ouput directory.");
my $Execution_Date = $SDK->getDate();
$SDK->createDirectory("$CFG_Ouput/$Execution_Date");
$Console->cleanDirectory("$CFG_Ouput",$CFG_Cache);

# CloseHandler sub
sub closeHandler {
    my $msg = shift;
    $Console->print($msg,0);
    $Console->close();
    $Console->copyTo("$CFG_Ouput/$Execution_Date");
    exit(1);
}

# ************************************************* #
# Check hubs list! (get hubs and pool ADE)
# ************************************************* #
$Console->print("Get hubs list !",5);
my @ArrayHub;
my $Primary_hub;
my %AvailableADE = ();
$| = 1;
eval {
    my $RC;
    ($RC,@ArrayHub) = $SDK->getArrayHubs();
    if($RC == NIME_OK) {
        foreach my $hub (@ArrayHub) {
            next if $hub->{domain} ne $CFG_Domain;
            $Console->print("Processing hub $hub->{name}");

            if($hub->{name} eq $CFG_OriginalHub) {
                $Primary_hub = $hub;
                $Console->print("Find origin hub $hub->{name}, skip to the next iteration!",2);
                next; # Skip registering of this one!
            }

            # Check ADE availability on each hub!
            $RC = $hub->probeVerify('automated_deployment_engine');
            if($RC == NIME_OK) {
                $Console->print("Successfully get alive response from ADE");
                $AvailableADE{$hub->{name}} = $hub;
            }
        }
    }
    else {
        $Console->print("Failed to get hubs list, RC => $RC!",0);
    }
};
closeHandler($@) if $@;
closeHandler('Failed to get original hub!') if not defined($Primary_hub);


# ************************************************* #
# Get primary packages!
# ************************************************* #
$| = 1;
my %PrimaryPackages = ();
eval {
    $Console->print("Get packages from primary hub!");
    my $RC;
    my $archive = $Primary_hub->archive();
    ($RC,%PrimaryPackages) = $archive->getPackages();
    if($RC == NIME_OK) {
        my $numberPackages = scalar keys %PrimaryPackages;
        $Console->print("Successfully Retrieving $numberPackages packages from primary hub!",3);

        if($CFG_UpdateRule) {
            $Console->print("Add packages synchronisation rules!");
            foreach my $PKG (values %PrimaryPackages) {
                if($PKG->{valid} == 1) {
                    my $sth = $DB->prepare("SELECT count(*) FROM NIMSOFT_hubs_packages WHERE name = ?");
                    $sth->execute($PKG->{name});
                    my $rows = $sth->fetch()->[0];
                    if ("$rows" eq "0") {
                        my $Success = $archive->ade_addPackageSyncRule($PKG);
                        if($Success == NIME_OK) {
                            $Console->print("Successfully add $PKG->{name} to the archive sync rules!",3);
                        }
                        else {
                            $Console->print("Failed to add $PKG->{name} to the archive sync rules!",1);
                        }
                    }
                    else {
                        $Console->print("No need to synchronise $PKG->{name} with version $PKG->{version} (NB Row => $rows)",3);
                    }
                    $sth->finish;
                }
            }
        }
    }
    else {
        closeHandler('Unable to get primary packages informations!');
    }
};
closeHandler($@) if $@;

# ************************************************* #
# Compare all hubs with primary and delete packages
# ************************************************* #
sub comparePackages {
    my $PKG = shift;
    my @Diff = ();
    my %Packages = %{ $PKG };

    # Delete package not present
    foreach my $Key (keys %Packages) {
        if(not exists($PrimaryPackages{$Key})) {
            $Console->print("Adding $Key to processing pool!");
            push(@Diff,$Packages{$Key});
            delete $Packages{$Key};
        }
    }

    return @Diff;
}

$| = 1;
$Console->print("Compare and delete bad packages processing starting !",5);
foreach my $hub (values %AvailableADE) {
    $Console->print("Processing difference on => $hub->{name}");
    my $archive = $hub->archive();
    my ($RC,%Packages) = $archive->getPackages();
    if($RC == NIME_OK) {
        my $totalNumber = scalar keys %Packages;
        $Console->print("Successfully retrieving $totalNumber packages informations",1);
        my (@Diff) = comparePackages(\%Packages);
        my $cleanNumber = scalar @Diff;

        if($cleanNumber > 0 && not $CFG_Audit) {
            $Console->print("Starting the cleaning of $cleanNumber packages!");
            my $failed_count = 0;
            foreach(@Diff) {
                my $deleteRC = $archive->deletePackage($_);
                if($deleteRC != NIME_OK) {
                    $Console->print("Failed to delete package $_->{name}",1);
                    $failed_count++;
                    if($failed_count > 5) {
                        $Console->print("Stop deleting because ADE on this hub seem broken!",1);
                        last;
                    }
                }
                else {
                    $Console->print("Successfully deleting package $_->{name}_$_->{version}");
                }
            }
        }
    }
    else {
        $Console->print("Failed to get Archives list!",1);
    }
}

# Restart ADE 
{
    my $PDS = pdsCreate(); 
    my ($RC,$RES) = nimNamedRequest("$Primary_hub->{clean_addr}/automated_deployment_engine","_restart",$PDS);
    pdsDelete($PDS);

    if($RC == NIME_OK) {
        $Console->print("Automated_deployment_engine on $Primary_hub->{name} successfully restarted.",3);
    }
    else {
        $Console->print("Failed to restart automated_deployment_engine on $Primary_hub->{name}.",1);
    }
}

# ************************************************* #
# End of the script!
# ************************************************* #
$Console->finalTime($ScriptExecutionTime);
$| = 1;
$SDK->doSleep(5);

$Console->copyTo("$CFG_Ouput/$Execution_Date");
$Console->close();
1;
