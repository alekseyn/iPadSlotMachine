//
//  ApplicationDelegate.m
//  iPadSlotMachine
//
//  Created by Tim Burks on 4/16/10.
//

#import "ApplicationDelegate.h"
#import "Motion.h"
#import "MasterViewController.h"
#import "SpinWheelViewController.h"
#import "SlotMachineHopperViewController.h"

ApplicationDelegate *DELEGATE;

#define HANDLE_AS_MASTER YES

// connection timeouts
#define TIMEOUT 60

@interface ApplicationDelegate (Internal)
- (void) addExternalDisplay:(UIScreen *) newScreen;
- (void) startConnection;
@end

@implementation ApplicationDelegate
@synthesize window, applicationRole, is_iPad;
@synthesize session;
@synthesize masterID, slaveHandleID, slaveHopperID, slaveReels;
@synthesize externalWindow;
@synthesize masterViewController, spinWheelViewController, slotMachineHopperViewController, handleViewController;
@synthesize numberOfReelsCurrentlySpinning;

UIAlertView *roleChooserAlert; 
UIAlertView *componentChooserAlert;
AVAudioPlayer *soundPlayer;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
	DELEGATE = self;
	
	[[UIApplication sharedApplication] setStatusBarHidden:YES];
	
	UIDevice *device = [UIDevice currentDevice];
	if ([device respondsToSelector:@selector(userInterfaceIdiom)]) {
		self.is_iPad = ([[UIDevice currentDevice] userInterfaceIdiom] == 1);
	} else {
		self.is_iPad = NO;
	}
	
	self.numberOfReelsCurrentlySpinning = 0;
	self.slaveReels = [NSMutableArray array];
	
	CGRect mainBounds = [[UIScreen mainScreen] bounds];
	self.window = [[[UIWindow alloc] initWithFrame:mainBounds] autorelease];
	
	UIImageView *backgroundView = [[[UIImageView alloc] 
									initWithImage:[UIImage imageNamed:@"MachineBackground.png"]] 
								   autorelease];
	backgroundView.frame = mainBounds;
	[window addSubview:backgroundView];
	backgroundView.contentMode = UIViewContentModeScaleAspectFill;
	
	// display role chooser
	roleChooserAlert = [[UIAlertView alloc]
						initWithTitle:@"iPad Slot Machine"
						message:@"Let's get started!"
						delegate:self
						cancelButtonTitle:nil
						otherButtonTitles:@"Create New Machine", 
						@"Join Existing Machine", 
						@"Test Machine Components",
						nil];
	[roleChooserAlert show];
	
	[self.window makeKeyAndVisible];
	
	// watch for external screens
#if 0
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(screenDidConnect:)
												 name:@"UIScreenDidConnectNotification"
											   object:nil];	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(screenDidDisconnect:)
												 name:@"UIScreenDidDisconnectNotification"
											   object:nil];	
	if ([UIScreen respondsToSelector:@selector(screens)]) {
		NSArray *screens = [UIScreen screens];
		if ([screens count] > 1) {
			[self addExternalDisplay:[screens objectAtIndex:1]];
		}
	}
#endif
	
	// play a sound on startup
	NSURL *fileURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:@"StartingGate" ofType:@"wav"]];
	NSError *error;
	if (!soundPlayer) {
		soundPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:fileURL error:&error];
	}
	[soundPlayer play];
	AudioServicesPlaySystemSound (kSystemSoundID_Vibrate);
	
	return YES;
}

#if 0
- (void) screenDidConnect:(NSNotification *) notification {
	NSLog(@"notification: %@", notification);
	UIScreen *newScreen = (UIScreen *) notification.object;
	[self addExternalDisplay:newScreen];
}

- (void) screenDidDisconnect:(NSNotification *) notification {
	NSLog(@"notification: %@", notification);
	UIScreen *oldScreen = (UIScreen *) notification.object;
	if (externalWindow && ([externalWindow screen] == oldScreen)) {
		self.externalWindow = nil;
	}
}

- (void) addExternalDisplay:(UIScreen *) newScreen 
{
	NSArray *modes = [newScreen availableModes];
	NSLog(@"screen modes: %@", modes);
	[newScreen setCurrentMode:[modes objectAtIndex:0]];
	NSLog(@"selecting mode %@", [newScreen currentMode]);
	
	self.externalWindow = [[[UIWindow alloc] 
							initWithFrame:[newScreen applicationFrame]]
						   autorelease];
	externalWindow.backgroundColor = [UIColor blueColor];
	[externalWindow setScreen:newScreen];
	[externalWindow makeKeyAndVisible];
}
#endif

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex 
{
	NSLog(@"pressed %d", buttonIndex);
	if (alertView == roleChooserAlert) {
		switch (buttonIndex) {
			case 0: 
				self.applicationRole = SlotMachineApplicationRoleMaster;
				if (HANDLE_AS_MASTER) {
					self.handleViewController = [[HandleViewController alloc] initWithNibName:@"HandleViewController" bundle:nil];
					[window addSubview:handleViewController.view];
				}
				else {
					self.masterViewController = [[[MasterViewController alloc] init] autorelease];
					[self.window addSubview:self.masterViewController.view];
				}

				[self startConnection];
				break;
			case 1:
				self.applicationRole = SlotMachineApplicationRoleSlaveSearching;
				[self startConnection];
				break;
			default: {
				componentChooserAlert = [[[UIAlertView alloc]
										  initWithTitle:@"Test Machine Components"
										  message:@"Choose a Component"
										  delegate:self
										  cancelButtonTitle:@"Cancel"
										  otherButtonTitles:@"Handle", 
										  @"Hopper", 
										  @"Reel", 
										  nil]
										 autorelease];
				[componentChooserAlert show];				
			}
		}
	} else if (alertView == componentChooserAlert) {
		if (buttonIndex == componentChooserAlert.cancelButtonIndex) {
			[roleChooserAlert show];
		} else if (buttonIndex == 1) {
			self.handleViewController = [[HandleViewController alloc] initWithNibName:@"HandleViewController" bundle:nil];
			[window addSubview:handleViewController.view];
		} else if (buttonIndex == 2) {
			self.slotMachineHopperViewController = [[SlotMachineHopperViewController alloc] initWithNibName:@"SlotMachineHopperViewController" bundle:nil];
			[window addSubview:slotMachineHopperViewController.view];
		} else if (buttonIndex == 3) {
			self.spinWheelViewController = [[[SpinWheelViewController alloc] init] autorelease];
			[self.window addSubview:spinWheelViewController.view];
		} else {
			// switch to the appropriate component mode for test purposes	
		}
	}
}

- (void) startConnection {
	id displayName = [NSString stringWithFormat:@"%@:%@",
					  [[UIDevice currentDevice] model],
					  [[UIDevice currentDevice] uniqueIdentifier]];
	GKSessionMode sessionMode = (self.applicationRole == SlotMachineApplicationRoleMaster) 
	? GKSessionModeServer : GKSessionModeClient;
	self.session = [[[GKSession alloc] initWithSessionID:@"iPadSlotMachine" 
											 displayName:displayName
											 sessionMode:sessionMode] autorelease];
	self.session.available = YES;
	self.session.delegate = self;
	[self.session setDataReceiveHandler:self withContext:nil];
}

- (void)session:(GKSession *)currentSession didReceiveConnectionRequestFromPeer:(NSString *)peerID
{
	NSString *peerName = [currentSession displayNameForPeer:peerID];
	UIAlertView *alert = [[[UIAlertView alloc]
						   initWithTitle:@"Received request from" message:peerName delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil]
						  autorelease];
	//[alert show];
	
	NSError *error;
	[currentSession acceptConnectionFromPeer:peerID error:&error];
}

NSString *nameForState(GKPeerConnectionState state) {
	switch (state) {
		case GKPeerStateAvailable:return @"available";
		case GKPeerStateUnavailable:return @"unavailable";
		case GKPeerStateConnected:return @"connected";
		case GKPeerStateDisconnected:return @"disconnected";
		case GKPeerStateConnecting:return @"connecting";
		default:return @"huh?";
	}
}

- (void)session:(GKSession *)currentSession peer:(NSString *)peerID didChangeState:(GKPeerConnectionState)state 
{
	NSString *peerName = [currentSession displayNameForPeer:peerID];
	UIAlertView *alert = [[[UIAlertView alloc]
						   initWithTitle:@"Peer did change state" 
						   message:[NSString stringWithFormat:@"Peer: %@ State:%@", peerName, nameForState(state)]
						   delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil]
						  autorelease];
	//[alert show];
	
	if (self.applicationRole == SlotMachineApplicationRoleMaster) {
		// handle connections for master
		
		// when a peer has connected, we need to assign it a role and then send that role to the peer.
		if (state == GKPeerStateConnected) {
			if ([[peerName substringToIndex:4] isEqualToString:@"iPad"]) {
				// the first iPads to connect are reels. 
				// when we have enough, we add a hopper.
				if ([self.slaveReels count] < 3) {
					[self.slaveReels addObject:peerID];
					[self sendMessage:[NSString stringWithFormat:@"become reel %d", [self.slaveReels count]] toPeer:peerID];
				} else {
					self.slaveHopperID = peerID;
					[self sendMessage:@"become hopper" toPeer:peerID];
				}
			} else { // iPhones and iPods are handles.
				self.slaveHandleID = peerID;
				[self sendMessage:@"become handle" toPeer:peerID];
			}
		} 
		
		
		
		else if (state == GKPeerStateDisconnected) {
			if ([self.slaveHandleID isEqualToString:peerID]) {
				self.slaveHandleID = nil;
			} else if ([self.slaveHopperID isEqualToString:peerID]) {
				self.slaveHopperID = nil;
			} else if ([self.slaveReels containsObject:peerID]) {
				[self.slaveReels removeObject:peerID];
			}
		}
		
	} else {
		
		// handle connections for slave
		if (state == GKPeerStateAvailable) {
			[currentSession connectToPeer:peerID withTimeout:TIMEOUT];
		}
		
		else if (state = GKPeerStateConnected) {
			self.spinWheelViewController = [[[SpinWheelViewController alloc] init] autorelease];
			[self.window addSubview:self.spinWheelViewController.view];
		}
	}
}

- (void) sendMessage:(NSString *) message toPeer:(NSString *) peerID
{
	NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];	
	NSError *error;
	[self.session sendData:data 
				   toPeers:[NSArray arrayWithObject:peerID]
			  withDataMode:GKSendDataReliable 
					 error:&error];
}

- (void) sendMessageToReels:(NSString *) message
{
	NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];	
	NSError *error;
	[self.session sendData:data 
				   toPeers:slaveReels
			  withDataMode:GKSendDataReliable 
					 error:&error];
}

- (void) receiveData:(NSData *)data fromPeer:(NSString *)peer inSession: (GKSession *)currentSession context:(void *)context {
	NSString *peerName = [currentSession displayNameForPeer:peer];
	UIAlertView *alert = [[[UIAlertView alloc]
						   initWithTitle:[NSString stringWithFormat:@"Received message from %@", peerName]
						   message:[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease]
						   delegate:nil 
						   cancelButtonTitle:@"OK" 
						   otherButtonTitles:nil]
						  autorelease];
	//[alert show];
	
	// the following code defines the language of commands that the master and slaves use to talk to one another.
	
	NSString *message = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
	NSArray *parts = [message componentsSeparatedByString:@" "];
	NSString *verb = [parts objectAtIndex:0];
	
	if ([verb isEqualToString:@"start"]) {	
		// slave reel starts spinning
		[self.spinWheelViewController doSpinForever:nil];
		//[self.spinWheelViewController doSpin:nil];
	} 
	
	else if ([verb isEqualToString:@"stop"]) {
		// slave reel stops spinning
		[self.spinWheelViewController doStop:nil];
	}
	
	else if ([verb isEqualToString:@"become"]) {
		// slave configures itself to be of the specified type
		NSString *kind = [parts objectAtIndex:1];
		if ([kind isEqualToString:@"hopper"]) {
			self.slotMachineHopperViewController = [[SlotMachineHopperViewController alloc] initWithNibName:@"SlotMachineHopperViewController" bundle:nil];
			[self.window addSubview:slotMachineHopperViewController.view];
		} else if ([kind isEqualToString:@"handle"]) {
			self.handleViewController = [[HandleViewController alloc] initWithNibName:@"HandleViewController" bundle:nil];
			[self.window addSubview:handleViewController.view];
		} else if ([kind isEqualToString:@"reel"]) {
			NSString *indexString = [parts objectAtIndex:2];			
			self.spinWheelViewController = [[[SpinWheelViewController alloc] init] autorelease];
			self.spinWheelViewController.index = [indexString intValue];
			[self.window addSubview:spinWheelViewController.view];
		}
	}
	
	else if ([verb isEqualToString:@"pulled"]) {
		// the handle sends this to the master to start the reels, we use the master controller to do that.
		[self.masterViewController start:self];
	} 
	
	else if ([verb isEqualToString:@"pressed"]) {
		// the handle sends this to the master when the button is pressed...
	}
	
	else if ([verb isEqualToString:@"stopped"]) {
		// a reel sends this to the master along with its index and stopping point
		self.numberOfReelsCurrentlySpinning--;
		if (self.numberOfReelsCurrentlySpinning == 0) {
			// incomplete...
			[self sendMessage:@"payout jackpot" toPeer:self.slaveHopperID];
		}
	}
	
	else if ([verb isEqualToString:@"payout"]) {
		// the master sends this to the hopper along with the size of the payout.
		// valid payouts are "lose" "win" "big" and "jackpot".
		NSString *payoutSize = [parts objectAtIndex:1];
		int prize;
		if ([payoutSize isEqualToString:@"lose"]) {
			prize = SlotMachineHopperWinSizeLose;
		} else if ([payoutSize isEqualToString:@"win"]) {
			prize = SlotMachineHopperWinSizeWin;
		} else if ([payoutSize isEqualToString:@"big"]) {
			prize = SlotMachineHopperWinSizeBigWin;
		} else if ([payoutSize isEqualToString:@"jackpot"]) {
			prize = SlotMachineHopperWinSizeJackpot;
		}
		[self.slotMachineHopperViewController dropCoins:prize];
	}
}

#pragma mark -
#pragma mark Handle Methods

- (void)handlePulled:(id)sender {
	NSLog(@"HANDLE PULLED!");
	if (HANDLE_AS_MASTER)
		[self sendMessageToReels:@"start"];
	else
		[self sendMessage:@"pulled handle" toPeer:self.masterID];
}


- (void)handleButtonPressed:(id)sender {
	NSLog(@"HANDLE BUTTON PRESSED!");
	if (HANDLE_AS_MASTER)
		[self sendMessageToReels:@"stop"];
	else
		[self sendMessage:@"pressed handle" toPeer:self.masterID];	
}

#pragma mark -
#pragma mark Reel Methods

- (void) SpinningEndedAt:(NSUInteger)number {
	// tell the master
	NSString *message = [NSString stringWithFormat:@"stopped %d %d", self.spinWheelViewController.index, number];
	[self sendMessage:message toPeer:self.masterID];
}

@end
