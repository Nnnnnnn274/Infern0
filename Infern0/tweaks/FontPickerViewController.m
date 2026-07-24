#import "FontPickerViewController.h"
#import "fonts.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface FontPickerViewController () <UIDocumentPickerDelegate>

@property NSArray *customFonts;
@property NSArray *repos;
@property UISegmentedControl *stylePicker;

@end


@implementation FontPickerViewController


- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"Font Overwrite";

    self.stylePicker =
    [[UISegmentedControl alloc] initWithItems:@[
        @"Standard",
        @"Mono",
        @"Italic"
    ]];

    self.stylePicker.selectedSegmentIndex = 0;

    self.navigationItem.rightBarButtonItem =
    [[UIBarButtonItem alloc]
     initWithImage:[UIImage systemImageNamed:@"shippingbox"]
     style:UIBarButtonItemStylePlain
     target:self
     action:@selector(showRepos)];

    self.customFonts = [Fonts loadFonts];
    self.repos = [Fonts loadRepositories];

}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}


- (NSInteger)tableView:(UITableView *)tableView
 numberOfRowsInSection:(NSInteger)section {

    switch(section)
    {
        case 0:
            return self.repos.count;

        case 1:
            return self.customFonts.count;

        default:
            return 2;
    }
}



- (NSString *)tableView:(UITableView *)tableView
titleForHeaderInSection:(NSInteger)section {

    switch(section)
    {
        case 0:
            return @"Font Repositories";

        case 1:
            return @"Imported Fonts";

        default:
            return @"Settings";
    }
}



- (UITableViewCell *)
tableView:(UITableView *)tableView
cellForRowAtIndexPath:(NSIndexPath *)indexPath {


    UITableViewCell *cell =
    [tableView dequeueReusableCellWithIdentifier:@"cell"];

    if(!cell)
    {
        cell =
        [[UITableViewCell alloc]
         initWithStyle:UITableViewCellStyleDefault
         reuseIdentifier:@"cell"];
    }


    if(indexPath.section == 0)
    {
        cell.textLabel.text =
        self.repos[indexPath.row];
    }


    else if(indexPath.section == 1)
    {
        NSDictionary *font =
        self.customFonts[indexPath.row];

        cell.textLabel.text =
        font[@"name"];

        cell.accessoryType =
        UITableViewCellAccessoryDisclosureIndicator;
    }


    else
    {
        if(indexPath.row == 0)
        {
            cell.contentView =
            self.stylePicker;
        }
        else
        {
            cell.textLabel.text = @"Import Font";
        }
    }


    return cell;
}

- (void)tableView:(UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *)indexPath {


    if(indexPath.section == 1)
    {
        NSDictionary *font =
        self.customFonts[indexPath.row];


        NSString *source =
        font[@"path"];


        NSString *target;


        switch(self.stylePicker.selectedSegmentIndex)
        {
            case 1:
                target = @"/var/mobile/Library/Fonts/Mono.ttf";
                break;

            case 2:
                target = @"/var/mobile/Library/Fonts/Italic.ttf";
                break;

            default:
                target = @"/var/mobile/Library/Fonts/Standard.ttf";
                break;
        }


        BOOL ok =
        [Fonts replaceFont:target
                withSource:source];


        if(ok)
        {
            [self showMessage:@"Font applied"];
        }
        else
        {
            [self showMessage:@"Failed"];
        }
    }


    if(indexPath.section == 2 &&
       indexPath.row == 1)
    {
        [self importFont];
    }

}

- (void)importFont {

    UIDocumentPickerViewController *picker =
    [[UIDocumentPickerViewController alloc]
     initForOpeningContentTypes:@[
        [UTType typeWithIdentifier:@"public.font"]
     ]
     asCopy:YES];


    picker.delegate = self;

    [self presentViewController:picker
                       animated:YES
                     completion:nil];
}



- (void)documentPicker:(UIDocumentPickerViewController *)controller
didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {


    if(urls.count)
    {
        [Fonts importFont:urls.firstObject];

        self.customFonts =
        [Fonts loadFonts];

        [self.tableView reloadData];
    }
}

- (void)showRepos {

    UIAlertController *alert =
    [UIAlertController
     alertControllerWithTitle:@"Font Repo"
     message:@"Add repository URL"
     preferredStyle:UIAlertControllerStyleAlert];


    [alert addTextFieldWithConfigurationHandler:nil];


    [alert addAction:
     [UIAlertAction
      actionWithTitle:@"Add"
      style:UIAlertActionStyleDefault
      handler:^(UIAlertAction *a){

        NSString *url =
        alert.textFields.firstObject.text;

        [Fonts addRepository:url];

        self.repos =
        [Fonts loadRepositories];

        [self.tableView reloadData];

    }]];


    [alert addAction:
     [UIAlertAction
      actionWithTitle:@"Cancel"
      style:UIAlertActionStyleCancel
      handler:nil]];


    [self presentViewController:alert
                       animated:YES
                     completion:nil];
}

- (void)showMessage:(NSString *)msg {

    UIAlertController *a =
    [UIAlertController
     alertControllerWithTitle:nil
     message:msg
     preferredStyle:UIAlertControllerStyleAlert];


    [a addAction:
     [UIAlertAction actionWithTitle:@"OK"
     style:UIAlertActionStyleCancel
     handler:nil]];


    [self presentViewController:a
                       animated:YES
                       completion:nil];
}

@end