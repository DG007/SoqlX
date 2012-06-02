//
//  DataSources.m
//  AppExplorer
//
//  Created by Simon Fell on 9/4/06.
//  Copyright 2006 Simon Fell. All rights reserved.
//

#import "DataSources.h"
#import "../sforce/zkDescribeSObject.h"
#import "../sforce/zkDescribeField.h"
#import "../sforce/zkChildRelationship.h"
#import "../sforce/zkSForceClient.h"
#import "DescribeOperation.h"
#import "HighlightTextFieldCell.h"

@interface DescribeListDataSource ()
-(void)updateFilter;
@end

@interface ZKDescribeField (Filtering)
-(BOOL)fieldMatchesFilter:(NSString *)filter;
@end

@implementation ZKDescribeField (Filtering)

-(BOOL)fieldMatchesFilter:(NSString *)filter {
	if (filter == nil) return NO;
	return [[self name] rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound;
}

@end

@implementation DescribeListDataSource

- (id)init {
	self = [super init];
	describeQueue = [[NSOperationQueue alloc] init];
	[describeQueue setMaxConcurrentOperationCount:2];
	return self;
}

- (void)dealloc {
	[types release];
	[sforce release];
	[operations release];
	[describes release];
	[describeQueue release];
	[filter release];
	[filteredTypes release];
	[outlineView release];
	[descGlobalSobjects release];
	[super dealloc];
}

- (void)setTypes:(NSArray *)t view:(NSOutlineView *)ov {
	outlineView = [ov retain];
	types = [t retain];
	describes = [[NSMutableDictionary alloc] init];
	operations = [[NSMutableDictionary alloc] init];
	
	NSMutableDictionary *byname = [NSMutableDictionary dictionary];
	for (ZKDescribeGlobalSObject *o in t)
		[byname setObject:o forKey:[[o name] lowercaseString]];
		
	descGlobalSobjects = [byname retain];
	/*
	for(NSString *sobject in t) {
		sobject = [sobject lowercaseString];
		DescribeOperation *op = [[DescribeOperation alloc] initForSObject:sobject cache:self];
		[op setQueuePriority:NSOperationQueuePriorityLow];
		[operations setObject:op forKey:sobject];
		[describeQueue addOperation:op];
	}*/
	[self updateFilter];
}

- (void)setSforce:(ZKSforceClient *)sf {
	sforce = [[sf copy] retain];
}

- (void)prioritizeDescribe:(NSString *)type {
	NSOperation *op = [operations objectForKey:[type lowercaseString]];
	[op setQueuePriority:NSOperationQueuePriorityHigh];
}

-(void)setFilteredTypes:(NSArray *)t {
	NSArray *old = filteredTypes;
	[filteredTypes autorelease];
	filteredTypes = [t retain];
	if (![old isEqualToArray:t])
		[outlineView reloadData];
}

-(BOOL)filterIncludesType:(NSString *)type {
	if ([type rangeOfString:filter options:NSCaseInsensitiveSearch].location != NSNotFound)
		return YES; // easy, type contains the filter clause
	if (![self hasDescribe:type]) 
		return NO;	// we haven't described it yet
	for (ZKDescribeField *f in [[self describe:type] fields]) {
		if ([f fieldMatchesFilter:filter])
			return YES;
	}
	return NO;
}

-(void)updateFilter {
	if ([filter length] == 0) {
		[self setFilteredTypes:types];
		return;
	}
	NSMutableArray *ft = [NSMutableArray array];
	for (ZKDescribeGlobalSObject *type in types) {
		if ([self filterIncludesType:[type name]])
			[ft addObject:type];
	}
	[self setFilteredTypes:ft];
}

- (NSString *)filter {
	return filter;
}

- (void)setFilter:(NSString *)filterValue {
	[filter autorelease];
	filter = [filterValue copy];
	[self updateFilter];
}

- (NSArray *)SObjects {
	return types;
}

- (int)numberOfRowsInTableView:(NSTableView *)v {
	return [filteredTypes count];
}

- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)tc row:(int)rowIdx {
	return [[filteredTypes objectAtIndex:rowIdx] name];
}

- (BOOL)isTypeDescribable:(NSString *)type {
	return nil != [descGlobalSobjects objectForKey:[type lowercaseString]];
}

- (BOOL)hasDescribe:(NSString *)type {
	return nil != [describes objectForKey:[type lowercaseString]];
}

- (ZKDescribeSObject *)describe:(NSString *)type {
	NSString *t = [type lowercaseString];
	ZKDescribeSObject * d = [describes objectForKey:t];
	if (d == nil) {
		if (![self isTypeDescribable:t]) 
			return nil; 
		d = [sforce describeSObject:t];
		[describes setObject:d forKey:t];
		[self performSelectorOnMainThread:@selector(updateFilter) withObject:nil waitUntilDone:NO];
	}
	return d;
}

// for use in an outline view
- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
	if (item == nil) return [filteredTypes count];
	return [[[self describe:item] fields] count];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item  {
	return item == nil || [item isKindOfClass:[NSString class]];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item {
	if (item == nil) return [[filteredTypes objectAtIndex:index] name];
	id f = [[[self describe:item] fields] objectAtIndex:index];
	return f;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
	if ([[[tableColumn headerCell] stringValue] isEqualToString:@"SObjects"]) {
		if ([item isKindOfClass:[NSString class]])
			return item;
		return [item name];
	}
	return nil;
}

-(NSCell *)outlineView:(NSOutlineView *)outlineView dataCellForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
	HighlightTextFieldCell *c = [tableColumn dataCell];
	[c setTextColor:[NSColor blackColor]];
	[c setFont:[NSFont systemFontOfSize:12.0f]];
	[c setZkStandout:NO];
	if ([item isKindOfClass:[ZKDescribeField class]]) {
		if ([item fieldMatchesFilter:filter]) {
			[c setFont:[NSFont boldSystemFontOfSize:13.0f]];
			[c setTextColor:[[NSColor blueColor] blendedColorWithFraction:0.5 ofColor:[NSColor blackColor]]];
			[c setZkStandout:YES];
		}
	}
	return c;
}

-(CGFloat)outlineView:(NSOutlineView *)ov heightOfRowByItem:(id)item {
	if ([item isKindOfClass:[ZKDescribeField class]]) {
		if ([item fieldMatchesFilter:filter]) {
			return [ov rowHeight] + 4;
		}
	}
    return [ov rowHeight];
}

@end

@implementation SObjectDataSource


- (id)initWithDescribe:(ZKDescribeSObject *)s {
	[super init];
	sobject = [s retain];
	
	NSMutableArray *t = [NSMutableArray arrayWithObjects:@"Name", @"Label", @"PluralLabel", @"Key Prefix", @"Custom", 
				@"Createable", @"Updateable", @"Activateable", @"Deleteable", @"Undeleteable", 
				@"Mergeable", @"Queryable", @"Retrieveable", @"Searchable", @"Layoutable",  
				@"Replicateable", @"Triggerable", @"URL for Edit", @"URL for Detail", @"URL for New", nil];
	NSArray *cr = [s childRelationships];
	if ([cr count] > 0) {
		NSString *sectionTitle = [NSString stringWithFormat:@"Relationships to %@", [sobject name]];
		NSAttributedString *boldTitle = [[NSAttributedString alloc] initWithString:sectionTitle attributes:[NSDictionary dictionaryWithObject:[NSFont boldSystemFontOfSize:11] forKey:NSFontAttributeName]];
		[t addObject:boldTitle]; 
		for (ZKChildRelationship *r in cr) {
			[t addObject:[NSString stringWithFormat:@"%@.%@", [r childSObject], [r field]]];
		}
	}
	titles = [t retain];
	return self;
}

- (void)dealloc {
	[sobject release];
	[titles release];
	[super dealloc];
}

- (NSString *)description {
	return [NSString stringWithFormat:@"SObject : %@", [sobject name]];
}

// for use in a table view
-(int)numberOfRowsInTableView:(NSTableView *)view {
	return [titles count];
}

-(id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)tc row:(int)rowIdx {
	if ([[tc identifier] isEqualToString:@"title"])
		return [titles objectAtIndex:rowIdx];

	SEL selectors[] = { @selector(name), @selector(label), @selector(labelPlural), @selector(keyPrefix), @selector(custom),			
						@selector(createable), @selector(updateable), @selector(activateable), @selector(deletable), @selector(undeleteable),
						@selector(mergeable), @selector(queryable), @selector(retrieveable), @selector(searchable), @selector(layoutable),
						@selector(replicateable), @selector(triggerable), @selector(urlEdit), @selector(urlDetail), @selector(urlNew) };

	int numSelectors = sizeof(selectors)/sizeof(*selectors);
	
	if (rowIdx < numSelectors) {
		SEL theSel = selectors[rowIdx];		
		id f = [sobject performSelector:theSel];
		const char *returnType = [[sobject methodSignatureForSelector:theSel] methodReturnType];
		if (returnType[0] == 'c') 	// aka char aka Bool			
			return f ? @"Yes" : @"";		
		return [sobject performSelector:theSel];
	}
	if (rowIdx == numSelectors)
		return @"";	// this is the value for the Child Relationships title row

	ZKChildRelationship *cr = [[sobject childRelationships] objectAtIndex:rowIdx - numSelectors -1];
	return [NSString stringWithFormat:@"%@", [cr relationshipName] == nil ? @"" : [cr relationshipName]];
}

@end

@implementation SObjectFieldDataSource
- (id)initWithDescribe:(ZKDescribeField *)f {
	[super init];
	field = [f retain];
	titles = [[NSArray arrayWithObjects:@"Name", @"Label", @"Type", @"Custom", @"Help Text",
					@"Length", @"Digits", @"Scale", @"Precision", @"Byte Length",
					@"Createable", @"Updatable", @"Default On Create", @"Calculated", @"AutoNumber",  
					@"Unique", @"Case Sensitive", @"Name Pointing", @"Sortable", @"Groupable",
					@"External Id", @"ID Lookup", @"Filterable", @"HTML Formatted", @"Name Field", @"Nillable", 
					@"Name Pointing", @"Reference To", @"Relationship Name", 
					@"Dependent Picklist", @"Controller Name", @"Restricted Picklist", 
					@"Value Formula", @"Default Formula", @"Relationship Order (CJOs)", @"Write Requires Read on Master (CJOs)", nil] retain];
	return self;
}

- (void)dealloc {
	[field release];
	[titles release];
	[super dealloc];
}

- (NSString *)description {
	return [NSString stringWithFormat:@"Field : %@.%@", [[field sobject] name], [field name]];
}

// for use in a table view
- (int)numberOfRowsInTableView:(NSTableView *)view {
	return [titles count];
}

- (id)tableView:(NSTableView *)view objectValueForTableColumn:(NSTableColumn *)tc row:(int)rowIdx {
	if ([[tc identifier] isEqualToString:@"title"])
		return [titles objectAtIndex:rowIdx];

	SEL selectors[] = { @selector(name), @selector(label), @selector(type), @selector(custom), @selector(inlineHelpText),
						@selector(length), @selector(digits), @selector(scale), @selector(precision), @selector(byteLength),			
						@selector(createable), @selector(updateable), @selector(defaultOnCreate), @selector(calculated), @selector(autoNumber),
						@selector(unique), @selector(caseSensitive), @selector(namePointing), @selector(sortable), @selector(groupable),
						@selector(externalId), @selector(idLookup), @selector(filterable), @selector(htmlFormatted), @selector(nameField), @selector(nillable),
						@selector(namePointing), @selector(referenceTo), @selector(relationshipName), 
						@selector(dependentPicklist), @selector(controllerName), @selector(restrictedPicklist),
						@selector(calculatedFormula), @selector(defaultValueFormula), @selector(relationshipOrder), @selector(writeRequiresMasterRead) };
	
	if (field == nil) return @"";
	id f = [field performSelector:selectors[rowIdx]];
	const char *returnType = [[field methodSignatureForSelector:selectors[rowIdx]] methodReturnType];
	
	if (returnType[0] == 'c')
		return f ? @"Yes" : @"";
	if (returnType[0] == 'i')  
		return f == 0 ? (id)@"" : (id)[NSNumber numberWithInt:(int)f];
	if (returnType[0] == '@') {
		if ([f isKindOfClass:[NSArray class]]) {
			if ([f count] == 0) return @"";
			return [f componentsJoinedByString:@", "];
		}
		return f;
	}
	NSLog(@"Unexpected return type of %c for selector %s", returnType, sel_getName(selectors[rowIdx]));
	return f;
}

@end

@implementation NoSelection 

-(BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(int)rowIndex {
	return NO;
}

@end
















