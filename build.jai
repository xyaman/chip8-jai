#import "Compiler";
#import "File";

#run {
    set_build_options_dc(.{do_output=false});
    make_directory_if_it_does_not_exist("./bin");

    w := compiler_create_workspace("chip8");

    options := get_build_options(w);
    options.output_executable_name = "chip8";
    options.output_path = "./bin";

    set_build_options(options, w);
    add_build_file("./src/main.jai", w);
}
