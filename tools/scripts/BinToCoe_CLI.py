import os
import sys


def bin_to_words(path):
    with open(path, "rb") as binfile:
        content = binfile.read(os.path.getsize(path))

    words = []
    for index in range(0, len(content), 4):
        chunk = content[index:index + 4]
        if len(chunk) < 4:
            chunk = chunk + bytes(4 - len(chunk))
        words.append(bytes(reversed(chunk)).hex())
    return words


def data_to_words(path):
    words = []
    with open(path, "r") as datafile:
        for line in datafile:
            word = line.strip()
            if not word:
                continue
            if word.startswith("@"):
                raise ValueError("@address directives are not supported in COE output")
            words.append(word)
    return words


def write_coe(words, outfile):
    with open(outfile, "w") as coefile:
        coefile.write("memory_initialization_radix=16;\n")
        coefile.write("memory_initialization_vector=\n")
        if words:
            for word in words[:-1]:
                coefile.write(f"{word},\n")
            coefile.write(f"{words[-1]};\n")
        else:
            coefile.write("0;\n")


def convert_to_coe(infile, outfile):
    lower_name = infile.lower()
    if lower_name.endswith(".bin"):
        words = bin_to_words(infile)
    else:
        words = data_to_words(infile)
    write_coe(words, outfile)


if __name__ == "__main__":
    if len(sys.argv) == 3:
        convert_to_coe(sys.argv[1], sys.argv[2])
    else:
        print("Usage: %s input.bin|input.data output.coe" % sys.argv[0])
        sys.exit(1)
