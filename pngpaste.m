/*
 * pngpaste
 */

#import "pngpaste.h"

void
usage ()
{
    fprintf(stderr,
        "Usage: %s [OPTIONS] <dest.png>\n"
        "\t-v\t" "Version" "\n"
        "\t-h,-?\t" "This usage" "\n"
        "\t-c\t" "Convert copied image to PNG format on the clipboard" "\n",
        APP_NAME);
}

void
fatal (const char *msg)
{
    if (msg != NULL) {
        fprintf(stderr, "%s: %s\n", APP_NAME, msg);
    }
}

void
version ()
{
    fprintf(stderr, "%s %s\n", APP_NAME, APP_VERSION);
}

ImageType
extractImageType (NSImage *image)
{
    ImageType imageType = ImageTypeNone;
    if (image != nil) {
        NSArray *reps = [image representations];
        NSImageRep *rep = [reps lastObject];
        if ([rep isKindOfClass:[NSPDFImageRep class]]) {
            imageType = ImageTypePDF;
        } else if ([rep isKindOfClass:[NSBitmapImageRep class]]) {
            imageType = ImageTypeBitmap;
        }
    }
    return imageType;
}

NSData *
renderImageData (NSImage *image, NSBitmapImageFileType bitmapImageFileType)
{
    ImageType imageType = extractImageType(image);
    switch (imageType) {
    case ImageTypeBitmap:
        return renderFromBitmap(image, bitmapImageFileType);
        break;
    case ImageTypePDF:
        return renderFromPDF(image, bitmapImageFileType);
        break;
    case ImageTypeNone:
    default:
        return nil;
        break;
    }
}

NSData *
renderFromBitmap (NSImage *image, NSBitmapImageFileType bitmapImageFileType)
{
    return [NSBitmapImageRep representationOfImageRepsInArray:[image representations]
                                                    usingType:bitmapImageFileType
                                                   properties:@{}];
}

NSData *
renderFromPDF (NSImage *image, NSBitmapImageFileType bitmapImageFileType)
{
    NSPDFImageRep *pdfImageRep =
        (NSPDFImageRep *)[[image representations] lastObject];
    CGFloat factor = PDF_SCALE_FACTOR;
    NSRect bounds = NSMakeRect(
        0, 0,
        pdfImageRep.bounds.size.width * factor,
        pdfImageRep.bounds.size.height * factor);

    NSImage *genImage = [[NSImage alloc] initWithSize:bounds.size];
    [genImage lockFocus];
    [[NSColor whiteColor] set];
    NSRectFill(bounds);
    [pdfImageRep drawInRect:bounds];
    [genImage unlockFocus];

    NSData *genImageData = [genImage TIFFRepresentation];
    return [[NSBitmapImageRep imageRepWithData:genImageData]
                       representationUsingType:bitmapImageFileType
                                    properties:@{}];
}

/*
 * Returns NSBitmapImageFileType based off of filename extension
 */
NSBitmapImageFileType
getBitmapImageFileTypeFromFilename (NSString *filename)
{
    static NSDictionary *lookup;
    if (lookup == nil) {
        lookup = @{
            @"gif": [NSNumber numberWithInt:NSBitmapImageFileTypeGIF],
            @"jpeg": [NSNumber numberWithInt:NSBitmapImageFileTypeJPEG],
            @"jpg": [NSNumber numberWithInt:NSBitmapImageFileTypeJPEG],
            @"png": [NSNumber numberWithInt:NSBitmapImageFileTypePNG],
            @"tif": [NSNumber numberWithInt:NSBitmapImageFileTypeTIFF],
            @"tiff": [NSNumber numberWithInt:NSBitmapImageFileTypeTIFF],
        };
    }
    NSBitmapImageFileType bitmapImageFileType = NSBitmapImageFileTypePNG;
    if (filename != nil) {
        NSArray *words = [filename componentsSeparatedByString:@"."];
        NSUInteger len = [words count];
        if (len > 1) {
            NSString *extension = (NSString *)[words objectAtIndex:(len - 1)];
            NSString *lowercaseExtension = [extension lowercaseString];
            NSNumber *value = lookup[lowercaseExtension];
            if (value != nil) {
                bitmapImageFileType = [value unsignedIntegerValue];
            }
        }
    }
    return bitmapImageFileType;
}

/*
 * Returns NSData from Pasteboard Image if available; otherwise nil
 */
NSData *
getPasteboardImageData (NSBitmapImageFileType bitmapImageFileType)
{
    NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
    NSImage *image = [[NSImage alloc] initWithPasteboard:pasteBoard];
    NSData *imageData = nil;

    if (image != nil) {
        imageData = renderImageData(image, bitmapImageFileType);
    }

    [image release];
    return imageData;
}

BOOL copyToClipboard (NSString *path)
{
    NSPasteboard *pasteBoard = [NSPasteboard generalPasteboard];
    
    NSURL *object = [[NSURL alloc] initFileURLWithPath:path];
    [pasteBoard clearContents];
    
    NSArray *objectsToCopy = [[NSArray alloc] initWithObjects:object, nil];
    BOOL pasted = [pasteBoard writeObjects:objectsToCopy];
 
    [object release];
    [objectsToCopy release];
    
    return pasted;
}

Parameters
parseArguments (int argc, char* const argv[])
{
    Parameters params;

    params.outputFile = nil;
    params.wantsVersion = NO;
    params.wantsUsage = NO;
    params.wantsStdout = NO;
    params.malformed = NO;
    params.onlyCovert = NO;

    int ch;
    while ((ch = getopt(argc, argv, "vch?")) != -1) {
        switch (ch) {
        case 'v':
            params.wantsVersion = YES;
            return params;
            break;
        case 'c':
            params.onlyCovert = YES;
            params.outputFile = [[NSString alloc] initWithString:@"/tmp/pasted-image.png"];
            return params;
            break;
        case 'h':
        case '?':
            params.wantsUsage = YES;
            return params;
            break;
        default:
            params.malformed = YES;
            return params;
            break;
        }
    }

    if (argc < 2) {
        params.malformed = YES;
    } else if (!strcmp(argv[1],STDOUT_FILENAME)) {
        params.wantsStdout = YES;
    } else {
        params.outputFile =
            [[NSString alloc] initWithCString:argv[1]
                                     encoding:NSUTF8StringEncoding];
    }
    return params;
}

int
main (int argc, char * const argv[])
{
    Parameters params = parseArguments(argc, argv);
    if (params.malformed) {
        usage();
        return EXIT_FAILURE;
    } else if (params.wantsUsage) {
        usage();
        return EXIT_SUCCESS;
    } else if (params.wantsVersion) {
        version();
        return EXIT_SUCCESS;
    }

    NSBitmapImageFileType bitmapImageFileType =
        getBitmapImageFileTypeFromFilename(params.outputFile);
    NSData *imageData = getPasteboardImageData(bitmapImageFileType);
    int exitCode;

    if (imageData != nil) {
        if (params.wantsStdout) {
            NSFileHandle *stdout =
                (NSFileHandle *)[NSFileHandle fileHandleWithStandardOutput];
            [stdout writeData:imageData];
            exitCode = EXIT_SUCCESS;
        } else {
            if ([imageData writeToFile:params.outputFile atomically:YES]) {
                exitCode = EXIT_SUCCESS;
            } else {
                fatal("Could not write to file!");
                exitCode = EXIT_FAILURE;
            }
        }
        if (params.onlyCovert) {
            if (copyToClipboard(@"/tmp/pasted-image.png")) {
                exitCode = EXIT_SUCCESS;
            }
        }
    } else {
        fatal("No image data found on the clipboard, or could not convert!");
        exitCode = EXIT_FAILURE;
    }

    return exitCode;
}
